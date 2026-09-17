import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'audio_session.dart';
import 'models.dart';
import 'music_playback_service.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'user_profile_service.dart';

/// ═══════════════════════ VIDEO PLAYBACK SERVICE ═══════════════════════
///
/// Owns the app-wide video player so a video keeps playing after the
/// player page is closed: pressing back shrinks it into the floating mini
/// player above the navbar, and tapping the mini player reopens the page
/// with playback, quality and speed intact.
class VideoPlaybackService extends ChangeNotifier with WidgetsBindingObserver {
  final NewPipeService _service;
  final MusicPlaybackService _music;
  final StorageService _storage;
  final UserProfileService _profile;

  VideoPlaybackService(this._storage, this._music, this._profile)
      : _service = NewPipeService() {
    WidgetsBinding.instance.addObserver(this);
    _restoreLastAudioSession();
  }

  Player? _player;
  VideoController? _controller;
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  Timer? _notifyThrottle;
  Duration _lastSavedPosition = Duration.zero;
  /// The last position the player itself reported (stream truth, never
  /// overridden by hand) — used to verify that a resume actually stuck.
  Duration? _rawPosition;

  /// Bumped on every open, quality swap, close, dispose and manual seek.
  /// A resume-correction loop from an older generation stands down as
  /// soon as its number is outdated — it never fights a newer action.
  int _resumeGeneration = 0;

  /// Bumped on every open / close / audio-mode toggle. enterAudioOnly's
  /// slow track switch validates against it once its await returns, so
  /// a toggle that raced with opening another video can never arm the
  /// audio mode on top of that new video (black screen with audio).
  int _sessionGeneration = 0;

  /// A restorable audio session from the previous app run: the mini
  /// player is back (paused) on the video that was listening, at the
  /// exact saved spot — no media is loaded until the first play press.
  bool _restoredSession = false;
  bool get needsReload => _restoredSession;

  VideoItem? currentVideo;
  DownloadItem? currentDownload;
  List<VideoStreamInfo> streams = [];
  VideoStreamInfo? currentStream;
  /// Selectable audio languages (original + dubs) for the current video.
  List<AudioTrackOption> audioTracks = [];
  AudioTrackOption? currentAudioTrack;
  double playbackSpeed = 1.0;

  /// Audio-only mode: the SAME player keeps running with its video
  /// track disabled (Flow-style) — position, quality and dub survive
  /// by design, there is no handoff to another engine and nothing to
  /// seek or wait for. The video surface returns via exitAudioOnly().
  bool audioOnlyMode = false;

  // ─────────── Notification bridge (audio-only mode) ───────────
  //
  // While audio-only runs, the shared audio-service handler (the
  // same one the Music tab uses) shows the video as a media
  // notification: play/pause/seek/stop from the lock screen route
  // straight back to this player, and its state is pushed from mpv.
  AdlessAudioHandler? _notificationHandler;
  List<StreamSubscription> _bridgeSubs = [];
  Timer? _bridgeTimer;
  bool _attachingBridge = false;

  bool loading = true;
  String? error;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  /// The floating mini player is visible (page closed, video still active).
  bool miniVisible = false;

  Player get player {
    _ensurePlayer();
    return _player!;
  }

  VideoController get controller {
    _ensurePlayer();
    return _controller!;
  }

  bool get hasActiveVideo => currentVideo != null;

  void _ensurePlayer() {
    if (_player != null) return;
    final player = Player();
    _player = player;
    _controller = VideoController(player);

    _playingSub = player.stream.playing.listen((playing) {
      isPlaying = playing;
      // Persist immediately when the user pauses so an app close never
      // loses more than a moment of progress.
      if (!playing && position.inMilliseconds > 0) {
        unawaited(_savePlaybackState());
      }
      notifyListeners();
    });
    _positionSub = player.stream.position.listen((pos) {
      position = pos;
      _rawPosition = pos;
      // Watch-percentage tracking for the recommendation profile —
      // keeps the session's high-water mark and checkpoints the event
      // to disk every 3 seconds alongside the playback state.
      _profile.updateWatchSession(pos, duration);
      // abs(): a backward seek must save too — without it the resume
      // spot would stay at the old high position until playback passed
      // it again.
      if ((pos - _lastSavedPosition).abs().inSeconds >= 3) {
        unawaited(_savePlaybackState(pos));
        unawaited(_profile.checkpointWatchSession());
      }
      // Throttled UI updates keep the mini player progress smooth without
      // rebuilding listeners on every single stream event.
      _notifyThrottle ??= Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => notifyListeners(),
      );
    });
    _durationSub = player.stream.duration.listen((d) {
      duration = d;
      notifyListeners();
    });
  }

  // ─────────── Open / close ───────────

  /// Starts [video]. If [download] is set, the local files are played
  /// instead of the network streams. [audioOnly] reloads a restored
  /// session straight into audio-only mode (track off, notification
  /// controls re-attached once the stream is live).
  Future<void> open(
    VideoItem video, {
    DownloadItem? download,
    bool audioOnly = false,
  }) async {
    final generation = ++_sessionGeneration;
    // A newer open / close / toggle must always win — this run stands
    // down at its next checkpoint instead of clobbering it. (Two quick
    // video taps used to leave the player playing one video while the
    // page showed another.)
    bool stale() => _sessionGeneration != generation;
    _resumeGeneration++;
    _restoredSession = false;
    // Pin the outgoing video's exact last spot before anything can go
    // wrong — a doomed open must never cost the previous video its
    // resume position.
    await _savePlaybackState();
    if (stale()) return;
    // Close out the previous video's watch session before starting the
    // new one, so its watch percentage lands in the profile.
    await _profile.endWatchSession();
    if (stale()) return;
    currentVideo = video;
    currentDownload = download;
    streams = [];
    currentStream = null;
    audioTracks = [];
    currentAudioTrack = null;
    playbackSpeed = 1.0;
    loading = true;
    error = null;
    // Reloading an audio session keeps the mini player it lives in.
    if (!audioOnly) miniVisible = false;
    position = Duration.zero;
    duration = Duration.zero;
    // The new video keeps its own save history — a leftover spot from
    // the previous video could otherwise clobber this one's resume.
    _lastSavedPosition = Duration.zero;
    notifyListeners();

    // Opening a video always leaves audio-only mode — release the
    // notification bridge BEFORE the music stop below, so a routed
    // stop can never reach close() and wipe the video being opened.
    if (audioOnlyMode) {
      audioOnlyMode = false;
      await _detachNotificationBridge();
      // mpv may still hold vid=no from the audio session — force the
      // track back on so a half-failed open can never leave a black
      // surface with the previous video's audio running under it.
      try {
        await _player?.setVideoTrack(VideoTrack.auto());
      } catch (_) {}
      unawaited(_storage.clearLastAudioSession());
    }
    // The restored-session reload re-arms immediately, so the UI keeps
    // its audio styling throughout the load.
    if (audioOnly) audioOnlyMode = true;

    // Only one audio surface: opening a video stops music first (a
    // stopped music session is a no-op, and the stop() guard keeps a
    // bridged video from ever being routed a stray music stop).
    await _music.stop();
    if (stale()) return;

    _ensurePlayer();
    try {
      if (download != null) {
        final videoPath = download.videoPath;
        if (videoPath == null || !File(videoPath).existsSync()) {
          throw StateError('The downloaded file is missing.');
        }
        _rawPosition = null;
        await _player!.open(Media(videoPath));
        if (stale()) return;
        final audioPath = download.audioPath;
        if (audioPath != null && File(audioPath).existsSync()) {
          await _player!
              .setAudioTrack(AudioTrack.uri(Uri.file(audioPath).toString()));
        }
        // Deterministic track state for local files too — a restored
        // audio session reloads with the track off, everything else
        // with the track guaranteed on.
        try {
          await _player!
              .setVideoTrack(audioOnly ? VideoTrack.no() : VideoTrack.auto());
        } catch (_) {}
        // Downloaded files resume too: the correction loop seeks to the
        // last watched spot once the file is actually live (see
        // _resumeAt).
        final resumeAt = _resumePosition(_storage.getPlaybackState(video.id));
        if (resumeAt > Duration.zero) {
          position = resumeAt;
          _resumePlayback(resumeAt);
        }
        await _player!.play();
      } else {
        // Hard timeouts: a hung extraction must surface as a retryable
        // error, not an eternal spinner on the player page.
        final available = await _service
            .getAvailableStreams(video.url)
            .timeout(const Duration(seconds: 25));
        if (stale()) return;
        if (available.isEmpty) {
          throw StateError('No playable stream found.');
        }
        final saved = _storage.getPlaybackState(video.id);
        final savedQuality = saved?['quality'];
        final savedFormat = saved?['format'];
        // Live streams keep no resume spot — their timeline is not the
        // recording's.
        final savedPosition =
            video.isLive ? Duration.zero : _resumePosition(saved);
        streams = available;
        currentStream = _selectDefaultStream(
            available, _storage.defaultQuality);
        for (final stream in available) {
          if (stream.quality == savedQuality &&
              stream.format == savedFormat) {
            currentStream = stream;
            break;
          }
        }
        // Dubbed audio tracks (free: the stream fetch is already cached).
        audioTracks = await _service
            .getAudioTracks(video.url)
            .timeout(const Duration(seconds: 12));
        if (stale()) return;
        currentAudioTrack = _pickDefaultAudioTrack();
        await _openStream(currentStream!, start: savedPosition,
            audioOnly: audioOnly);
        await _player!.play();
      }
      if (audioOnly) {
        // The restored audio session is live again — notification
        // controls return with it.
        unawaited(_attachNotificationBridge());
      }
      await _player!.setRate(playbackSpeed);
    } catch (e) {
      // A newer session owns the UI now — a stale failure must not
      // clobber its state.
      if (stale()) return;
      error = e.toString();
      _resumeGeneration++;
      // A failed open must never leave the previous video's audio
      // playing under this video's error page, nor a dead session the
      // mini player could tap into — stop the engine and clear the
      // session. The page keeps showing the error + Retry.
      isPlaying = false;
      await _player?.stop();
      currentVideo = null;
      currentDownload = null;
      currentStream = null;
      streams = [];
      audioTracks = [];
      currentAudioTrack = null;
      position = Duration.zero;
      duration = Duration.zero;
      _restoredSession = false;
    } finally {
      if (!stale()) {
        loading = false;
        // Session tracking starts once the stream is actually live — a
        // failed open leaves no phantom watch event.
        if (error == null) {
          _profile.beginWatchSession(video);
        }
        notifyListeners();
      }
    }
  }

  /// The player page is visible again for the already loaded video.
  void resumePage() {
    miniVisible = false;
    notifyListeners();
  }

  /// The user left the player page — keep playing in the mini player.
  void minimize() {
    if (currentVideo == null) return;
    miniVisible = true;
    notifyListeners();
  }

  /// Stops playback and clears everything (mini player close button).
  Future<void> close() async {
    _resumeGeneration++;
    _sessionGeneration++;
    _restoredSession = false;
    if (audioOnlyMode) {
      audioOnlyMode = false;
      await _detachNotificationBridge();
      unawaited(_storage.clearLastAudioSession());
    }
    await _profile.endWatchSession();
    unawaited(_savePlaybackState());
    await _player?.stop();
    currentVideo = null;
    currentDownload = null;
    currentStream = null;
    streams = [];
    audioTracks = [];
    currentAudioTrack = null;
    error = null;
    loading = false;
    isPlaying = false;
    miniVisible = false;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
  }

  // ─────────── Controls ───────────

  /// Audio-only mode: keeps the SAME player running with its video
  /// track disabled — the audio (with whatever dub is selected)
  /// continues from the current spot with the exact position,
  /// quality and speed preserved. There is no stream handoff and no
  /// seek to wait for, so this can never stall. The notification
  /// bridge attaches in the background and brings lock-screen
  /// controls (play/pause/seek/stop) with it.
  ///
  /// Returns false when the mode could not be entered (no video,
  /// live stream, or the track switch was refused) — the video then
  /// keeps playing unchanged.
  Future<bool> enterAudioOnly() async {
    final video = currentVideo;
    final player = _player;
    if (video == null || video.isLive || player == null) return false;
    if (audioOnlyMode) return true;
    final generation = ++_sessionGeneration;
    try {
      await player
          .setVideoTrack(VideoTrack.no())
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      return false;
    }
    // The slow track switch raced with something — another video
    // opened, the session closed, or a newer toggle happened. Arming
    // the mode now would disable the track of whatever is playing
    // instead (a black screen with audio) — restore the track and
    // stand down.
    if (_sessionGeneration != generation || currentVideo?.id != video.id) {
      try {
        await player.setVideoTrack(VideoTrack.auto());
      } catch (_) {}
      return false;
    }
    audioOnlyMode = true;
    unawaited(_savePlaybackState());
    notifyListeners();
    // Background audio + notification controls. Runs after the toggle
    // so the UI reacts instantly; the notification appears once the
    // (shared) audio service is ready.
    unawaited(_attachNotificationBridge());
    return true;
  }

  /// Returns to video mode: re-enables the video track on the same
  /// player and dismisses the notification. Playback continues at the
  /// exact spot the audio reached — nothing is reloaded or re-seeked.
  Future<void> exitAudioOnly() async {
    if (!audioOnlyMode) return;
    _sessionGeneration++;
    audioOnlyMode = false;
    try {
      await _player?.setVideoTrack(VideoTrack.auto());
    } catch (_) {}
    unawaited(_savePlaybackState());
    await _detachNotificationBridge();
    notifyListeners();
  }

  // ─────────── Notification bridge ───────────

  /// Borrows the shared media notification while audio-only runs.
  /// Attach happens in the background: a cold audio-service start can
  /// take a moment, and the mode itself must never wait on it.
  Future<void> _attachNotificationBridge() async {
    if (_notificationHandler != null || _attachingBridge) return;
    _attachingBridge = true;
    try {
      final handler = await sharedAudioHandler();
      final player = _player;
      final video = currentVideo;
      if (!audioOnlyMode || player == null || video == null) return;
      _notificationHandler = handler;
      handler.attachVideoAudio(VideoAudioController(
        play: () async => player.play(),
        pause: () async => player.pause(),
        seek: (position) => seekTo(position),
        stop: () => close(),
      ));
      handler.setVideoMediaItem(MediaItem(
        id: 'audio:${video.id}',
        title: video.title,
        artist: video.uploader,
        artUri: video.thumbnailUrl.isEmpty
            ? null
            : Uri.tryParse(video.thumbnailUrl),
        duration: duration > Duration.zero ? duration : null,
      ));
      _bridgeSubs = [
        player.stream.playing.listen((_) => _pushBridgeState()),
        player.stream.buffering.listen((_) => _pushBridgeState()),
        player.stream.completed.listen((_) => _pushBridgeState()),
        player.stream.duration.listen((d) {
          handler.updateVideoDuration(d);
          _pushBridgeState();
        }),
      ];
      // Android extrapolates the progress bar between pushes from
      // updatePosition + updateTime, so a slow heartbeat is plenty.
      _bridgeTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pushBridgeState(),
      );
      _pushBridgeState();
    } catch (_) {
      // The notification is a bonus — audio-only works without it.
      await _detachNotificationBridge();
    } finally {
      _attachingBridge = false;
    }
  }

  /// Releases the notification surface and dismisses the notification.
  Future<void> _detachNotificationBridge() async {
    _bridgeTimer?.cancel();
    _bridgeTimer = null;
    final subs = _bridgeSubs;
    _bridgeSubs = [];
    for (final sub in subs) {
      await sub.cancel();
    }
    final handler = _notificationHandler;
    _notificationHandler = null;
    if (handler != null) await handler.detachVideoAudio();
  }

  /// Mirrors the player's live state into the media notification.
  void _pushBridgeState() {
    final handler = _notificationHandler;
    final player = _player;
    if (handler == null || player == null || !audioOnlyMode) return;
    final processing = player.state.completed
        ? AudioProcessingState.completed
        : player.state.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready;
    handler.pushVideoState(
      playing: isPlaying,
      position: position,
      buffered: player.state.buffer,
      processing: processing,
    );
  }

  Future<void> togglePlayPause() async {
    if (currentVideo == null) return;
    // A restored session (previous app run) has no media loaded yet —
    // the first play press reloads it, audio-only, at the saved spot.
    if (_restoredSession) {
      _restoredSession = false;
      final video = currentVideo!;
      await open(video, audioOnly: true);
      if (error != null) {
        // The reload failed (offline, stream expired) — drop the ghost
        // session instead of leaving dead controls behind.
        await close();
      } else if (currentVideo?.id == video.id) {
        // Toggled straight from the mini player: it stays around
        // under whatever screen is on top.
        miniVisible = true;
        notifyListeners();
      }
      return;
    }
    if (isPlaying) {
      await _player?.pause();
    } else {
      // Resuming the video is also an audio surface: music yields.
      unawaited(_music.stop());
      await _player?.play();
    }
  }

  Future<void> seekBy(Duration delta) async {
    if (currentVideo == null) return;
    final target = position + delta;
    await seekTo(
      target < Duration.zero ? Duration.zero : target,
    );
  }

  Future<void> seekTo(Duration target) async {
    if (currentVideo == null) return;
    // A manual seek takes priority — any pending resume correction
    // stands down so it cannot drag the position back.
    _resumeGeneration++;
    await _player?.seek(target);
    position = target;
    unawaited(_savePlaybackState(target));
    notifyListeners();
  }

  Future<void> changeQuality(VideoStreamInfo stream) async {
    if (currentVideo == null) return;
    final previous = currentStream;
    final wasPlaying = isPlaying;
    final pos = position;
    try {
      await _openStream(stream, start: pos);
      currentStream = stream;
    } catch (_) {
      // The new quality refused to load — fall back to the previous
      // stream at the same position instead of killing playback.
      if (previous != null && previous != stream) {
        try {
          await _openStream(previous, start: pos);
        } catch (_) {}
      }
    }
    if (wasPlaying) {
      await _player?.play();
    } else {
      await _player?.pause();
    }
    unawaited(_savePlaybackState(pos));
    notifyListeners();
  }

  Future<void> changeSpeed(double speed) async {
    playbackSpeed = speed;
    await _player?.setRate(speed);
    notifyListeners();
  }

  /// Chooses the audio language for a fresh video: the user's remembered
  /// preference first, then the original track, then the first available.
  AudioTrackOption? _pickDefaultAudioTrack() {
    if (audioTracks.isEmpty) return null;
    final preferred = _storage.preferredAudioLocale;
    if (preferred.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.locale == preferred && !track.isOriginal) return track;
      }
    }
    for (final track in audioTracks) {
      if (track.isOriginal) return track;
    }
    return audioTracks.first;
  }

  /// Switches the audio language (dub) on the fly — mpv swaps the external
  /// audio track without restarting the video. The choice is remembered for
  /// future videos that carry the same dub.
  Future<void> setAudioTrackOption(AudioTrackOption track) async {
    if (currentVideo == null) return;
    currentAudioTrack = track;
    try {
      await _player?.setAudioTrack(AudioTrack.uri(
        track.url,
        title: track.label,
        language: track.locale,
      ));
    } catch (_) {}
    if (!track.isOriginal && track.locale.isNotEmpty) {
      unawaited(_storage.setPreferredAudioLocale(track.locale));
    }
    notifyListeners();
  }

  /// Pauses the background (mini player) video without clearing it — used
  /// when Shorts start so two things never play at once.
  Future<void> pauseIfPlaying() async {
    if (_player != null && isPlaying) {
      await _player!.pause();
    }
  }

  Future<void> _openStream(VideoStreamInfo stream,
      {Duration? start, bool audioOnly = false}) async {
    final startAt =
        start != null && start.inMilliseconds > 1500 ? start : null;
    _rawPosition = null;
    await _player?.open(Media(stream.url, start: startAt));
    // The picked audio language wins; adaptive streams fall back to the
    // extractor-paired original audio. Applied before the resume loop
    // starts, so a track swap can never wipe out the restored position.
    final audioUrl = currentAudioTrack?.url ?? stream.audioUrl;
    if (audioUrl != null) {
      await _player?.setAudioTrack(AudioTrack.uri(
        audioUrl,
        title: currentAudioTrack?.label,
        language: currentAudioTrack?.locale,
      ));
    }
    // A fresh media load resets mpv's track selection — make the track
    // state deterministic on every load: audio-only stays audio-only,
    // and every other load guarantees the track is ON (a leftover
    // vid=no can never black-screen the next video).
    final stayAudioOnly = audioOnlyMode || audioOnly;
    try {
      await _player?.setVideoTrack(
          stayAudioOnly ? VideoTrack.no() : VideoTrack.auto());
    } catch (_) {}
    if (startAt != null) {
      position = startAt;
      // Some stream types (adaptive video-only URLs in particular)
      // silently ignore the load-time start hint — and mpv can drop a
      // seek issued while the file is still loading. _resumeAt makes
      // the resume deterministic instead of hoping one seek sticks.
      _resumePlayback(startAt);
    }
  }

  /// Where to resume [video]: the saved spot, unless the video was
  /// (almost) finished last time — finished videos start over, like
  /// the official app.
  Duration _resumePosition(Map<String, dynamic>? saved) {
    final posMs = (saved?['positionMs'] as int?) ?? 0;
    final durMs = (saved?['durationMs'] as int?) ?? 0;
    if (posMs < 1500) return Duration.zero;
    if (durMs > 0 && posMs >= durMs * 0.97) return Duration.zero;
    return Duration(milliseconds: posMs);
  }

  /// Starts the resume correction loop for [target] under a fresh
  /// generation — any older loop stands down immediately.
  void _resumePlayback(Duration target) {
    final generation = ++_resumeGeneration;
    unawaited(_resumeAt(target, generation));
  }

  /// Deterministic resume. mpv can silently drop a seek issued while
  /// the file is still loading — which is exactly the state a freshly
  /// started app is in (cold player, cold network, adaptive stream
  /// URLs). One early seek plus one late check is therefore not
  /// enough. Instead:
  ///
  /// 1. wait (bounded) until the stream is actually live,
  /// 2. seek to the target,
  /// 3. keep watching the player-reported position and re-seek
  ///    whenever it is still sitting at the wrong spot.
  ///
  /// The loop stands down as soon as the position matches, the user
  /// seeks manually, or another open / quality swap takes over.
  Future<void> _resumeAt(Duration target, int generation) async {
    // Phase 1 — the file is live once the player reports a duration or
    // its first position; seeking before that is the dropped-seek
    // window. Warm swaps (quality change) skip the wait instantly.
    var waited = 0;
    while (_resumeGeneration == generation &&
        _rawPosition == null &&
        duration <= Duration.zero &&
        waited < 4000) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      waited += 150;
    }
    if (_resumeGeneration != generation || _player == null) return;
    try {
      await _player!.seek(target);
    } catch (_) {}
    if (_resumeGeneration != generation) return;
    position = target;
    notifyListeners();
    // Phase 2 — watchdog: re-seek while the player still reports a
    // spot far before the target (start hint AND first seek both
    // dropped on a slow-loading stream). Buffers count as "keep
    // waiting", not as failure.
    var elapsed = 0;
    while (_resumeGeneration == generation && elapsed < 12000) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      elapsed += 600;
      if (_resumeGeneration != generation || _player == null) return;
      final raw = _rawPosition;
      // No position reports yet — still buffering; keep waiting.
      if (raw == null) continue;
      // At (or past) the target — the resume stuck, hands off.
      if (raw > target - const Duration(seconds: 3)) break;
      try {
        await _player!.seek(target);
      } catch (_) {}
      if (_resumeGeneration != generation) return;
      position = target;
      notifyListeners();
    }
  }

  VideoStreamInfo _selectDefaultStream(
    List<VideoStreamInfo> available,
    String preference,
  ) {
    // "Auto" uses a connection-friendly 720p target instead of always
    // starting the most bandwidth-intensive stream.
    final target = preference == 'Auto'
        ? 720
        : int.tryParse(preference.replaceAll('p', '')) ?? 720;
    final ranked = available
        .map((stream) => (stream: stream, rank: _qualityRank(stream.quality)))
        .where((item) => item.rank > 0)
        .toList();
    final atOrBelowTarget =
        ranked.where((item) => item.rank <= target).toList();
    if (atOrBelowTarget.isNotEmpty) return atOrBelowTarget.first.stream;
    return ranked.isNotEmpty ? ranked.last.stream : available.first;
  }

  int _qualityRank(String quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  Future<void> _savePlaybackState([Duration? pos]) async {
    final video = currentVideo;
    if (video == null) return;
    final current = pos ?? position;
    // Nothing worth storing yet — never overwrite a good resume spot
    // with an empty one.
    if (current.inMilliseconds <= 0) return;
    _lastSavedPosition = current;
    var quality = currentStream?.quality;
    var format = currentStream?.format;
    if (currentStream == null) {
      // No live stream (a restored session): keep the saved choice —
      // never wipe a good quality/format with nulls.
      final saved = _storage.getPlaybackState(video.id);
      quality = saved?['quality'] as String?;
      format = saved?['format'] as String?;
    }
    await _storage.savePlaybackState(
      videoId: video.id,
      position: current,
      duration: duration,
      quality: quality,
      format: format,
    );
    // While audio-only runs, the same spot also feeds the restorable
    // session record — an app close mid-audio brings the mini player
    // back on the next run, paused at this exact position.
    if (audioOnlyMode) {
      await _storage.saveLastAudioSession(
        videoId: video.id,
        position: current,
        duration: duration,
      );
    }
  }

  /// Brings back an audio-only session that was cut off by the app
  /// being closed: the mini player reappears (paused) on the video
  /// that was listening, at the exact saved spot. The first play
  /// press reloads the stream; until then no player, no notification
  /// and no network are touched.
  void _restoreLastAudioSession() {
    try {
      final record = _storage.getLastAudioSession();
      if (record == null) return;
      final videoId = record['videoId'] as String?;
      final posMs = (record['positionMs'] as int?) ?? 0;
      final durMs = (record['durationMs'] as int?) ?? 0;
      if (videoId == null || videoId.isEmpty || posMs < 1500) return;
      // A (near) finished session is not worth resurrecting.
      if (durMs > 0 && posMs >= durMs * 0.97) return;
      // Full metadata comes from history — no network needed.
      VideoItem? item;
      for (final entry in _storage.getHistory()) {
        if (entry.id == videoId) {
          item = entry;
          break;
        }
      }
      if (item == null || item.isLive) return;
      currentVideo = item;
      position = Duration(milliseconds: posMs);
      duration = Duration(milliseconds: durMs);
      audioOnlyMode = true;
      _restoredSession = true;
      miniVisible = true;
      loading = false;
    } catch (_) {
      // A corrupt record must never block startup.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Sequential save → checkpoint → flush: the write must be ISSUED
      // (and the box flushed) before the OS can reap the process —
      // parallel unawaited calls could lose the very last spot.
      unawaited(() async {
        await _savePlaybackState();
        await _profile.checkpointWatchSession();
        await _storage.flushPlayback();
      }());
    }
  }

  @override
  void dispose() {
    _resumeGeneration++;
    unawaited(_detachNotificationBridge());
    unawaited(_profile.endWatchSession());
    WidgetsBinding.instance.removeObserver(this);
    _notifyThrottle?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
