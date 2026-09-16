import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

  VideoItem? currentVideo;
  DownloadItem? currentDownload;
  List<VideoStreamInfo> streams = [];
  VideoStreamInfo? currentStream;
  /// Selectable audio languages (original + dubs) for the current video.
  List<AudioTrackOption> audioTracks = [];
  AudioTrackOption? currentAudioTrack;
  double playbackSpeed = 1.0;

  /// Audio-only mode: playback keeps running but the video surface is
  /// hidden (the player page shows a placeholder instead). Lets users
  /// listen in the background feel without PiP.
  bool audioOnlyMode = false;

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
        _savePlaybackState();
      }
      notifyListeners();
    });
    _positionSub = player.stream.position.listen((pos) {
      position = pos;
      _rawPosition = pos;
      // Watch-percentage tracking for the recommendation profile —
      // keeps the session's high-water mark and checkpoints the event
      // to disk every 5 seconds alongside the playback state.
      _profile.updateWatchSession(pos, duration);
      if ((pos - _lastSavedPosition).inSeconds >= 5) {
        _savePlaybackState(pos);
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
  /// instead of the network streams.
  Future<void> open(
    VideoItem video, {
    DownloadItem? download,
  }) async {
    // Close out the previous video's watch session before starting the
    // new one, so its watch percentage lands in the profile.
    await _profile.endWatchSession();
    currentVideo = video;
    currentDownload = download;
    streams = [];
    currentStream = null;
    audioTracks = [];
    currentAudioTrack = null;
    playbackSpeed = 1.0;
    audioOnlyMode = false; // audio-only is a per-video choice
    loading = true;
    error = null;
    miniVisible = false;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    // Only one audio surface: video playback pauses music.
    unawaited(_music.stop());

    _ensurePlayer();
    try {
      if (download != null) {
        final videoPath = download.videoPath;
        if (videoPath == null || !File(videoPath).existsSync()) {
          throw StateError('The downloaded file is missing.');
        }
        await _player!.open(Media(videoPath));
        final audioPath = download.audioPath;
        if (audioPath != null && File(audioPath).existsSync()) {
          await _player!
              .setAudioTrack(AudioTrack.uri(Uri.file(audioPath).toString()));
        }
        // Downloaded files resume too: seek to the last watched spot
        // before playback starts.
        final resumeAt = _resumePosition(_storage.getPlaybackState(video.id));
        if (resumeAt > Duration.zero) {
          position = resumeAt;
          await _player!.seek(resumeAt);
          unawaited(_verifyResume(resumeAt));
        }
        await _player!.play();
      } else {
        // Hard timeouts: a hung extraction must surface as a retryable
        // error, not an eternal spinner on the player page.
        final available = await _service
            .getAvailableStreams(video.url)
            .timeout(const Duration(seconds: 25));
        if (available.isEmpty) {
          throw StateError('No playable stream found.');
        }
        final saved = _storage.getPlaybackState(video.id);
        final savedQuality = saved?['quality'];
        final savedFormat = saved?['format'];
        final savedPosition = _resumePosition(saved);
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
        currentAudioTrack = _pickDefaultAudioTrack();
        await _openStream(currentStream!, start: savedPosition);
        await _player!.play();
      }
      await _player!.setRate(playbackSpeed);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      // Session tracking starts once the stream is actually live — a
      // failed open leaves no phantom watch event.
      if (error == null) {
        _profile.beginWatchSession(video);
      }
      notifyListeners();
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
    await _profile.endWatchSession();
    _savePlaybackState();
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
    audioOnlyMode = false;
    miniVisible = false;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
  }

  // ─────────── Controls ───────────

  /// Toggles audio-only mode for the current video. Audio keeps playing;
  /// only the video surface is hidden while the mode is on.
  void toggleAudioOnlyMode() {
    if (currentVideo == null) return;
    audioOnlyMode = !audioOnlyMode;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (currentVideo == null) return;
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
    await _player?.seek(target);
    position = target;
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
    _savePlaybackState(pos);
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

  Future<void> _openStream(VideoStreamInfo stream, {Duration? start}) async {
    final startAt =
        start != null && start.inMilliseconds > 1500 ? start : null;
    _rawPosition = null;
    await _player?.open(Media(stream.url, start: startAt));
    if (startAt != null) {
      position = startAt;
      // Some stream types (adaptive video-only URLs in particular)
      // silently ignore the load-time start hint — an explicit seek
      // right after the open makes the resume deterministic.
      await _player?.seek(startAt);
      unawaited(_verifyResume(startAt));
    }
    // The picked audio language wins; adaptive streams fall back to the
    // extractor-paired original audio.
    final audioUrl = currentAudioTrack?.url ?? stream.audioUrl;
    if (audioUrl != null) {
      await _player?.setAudioTrack(AudioTrack.uri(
        audioUrl,
        title: currentAudioTrack?.label,
        language: currentAudioTrack?.locale,
      ));
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

  /// Second chance for a resume: a moment after the swap, if the player
  /// is still sitting at the very beginning despite a requested start,
  /// seek once more. Covers the rare streams that drop both the start
  /// hint and the first seek.
  Future<void> _verifyResume(Duration target) async {
    final videoId = currentVideo?.id;
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (currentVideo?.id != videoId || _player == null) return;
    final raw = _rawPosition ?? Duration.zero;
    if (raw < const Duration(seconds: 3) &&
        target >= const Duration(seconds: 3)) {
      await _player!.seek(target);
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

  void _savePlaybackState([Duration? pos]) {
    final video = currentVideo;
    if (video == null) return;
    final current = pos ?? position;
    // Nothing worth storing yet — never overwrite a good resume spot
    // with an empty one.
    if (current.inMilliseconds <= 0) return;
    _lastSavedPosition = current;
    final stream = currentStream;
    unawaited(_storage.savePlaybackState(
      videoId: video.id,
      position: current,
      duration: duration,
      quality: stream?.quality,
      format: stream?.format,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
      // Backgrounded with the mini player still going: checkpoint now;
      // the session continues and endWatchSession runs on the next
      // open/close.
      unawaited(_profile.checkpointWatchSession());
    }
  }

  @override
  void dispose() {
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
