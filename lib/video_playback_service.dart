import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'music_playback_service.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';

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

  VideoPlaybackService(this._storage, this._music)
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

  VideoItem? currentVideo;
  DownloadItem? currentDownload;
  List<VideoStreamInfo> streams = [];
  VideoStreamInfo? currentStream;
  double playbackSpeed = 1.0;

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
      if ((pos - _lastSavedPosition).inSeconds >= 5) {
        _savePlaybackState(pos);
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
    currentVideo = video;
    currentDownload = download;
    streams = [];
    currentStream = null;
    playbackSpeed = 1.0;
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
        await _player!.play();
      } else {
        final available = await _service.getAvailableStreams(video.url);
        if (available.isEmpty) {
          throw StateError('No playable stream found.');
        }
        final saved = _storage.getPlaybackState(video.id);
        final savedQuality = saved?['quality'];
        final savedFormat = saved?['format'];
        final savedPosition = Duration(
          milliseconds: (saved?['positionMs'] as int?) ?? 0,
        );
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
        await _openStream(currentStream!, start: savedPosition);
        await _player!.play();
      }
      await _player!.setRate(playbackSpeed);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
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
    _savePlaybackState();
    await _player?.stop();
    currentVideo = null;
    currentDownload = null;
    currentStream = null;
    streams = [];
    error = null;
    loading = false;
    isPlaying = false;
    miniVisible = false;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
  }

  // ─────────── Controls ───────────

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
    final wasPlaying = isPlaying;
    final pos = position;
    await _openStream(stream, start: pos);
    if (wasPlaying) {
      await _player?.play();
    } else {
      await _player?.pause();
    }
    currentStream = stream;
    _savePlaybackState(pos);
    notifyListeners();
  }

  Future<void> changeSpeed(double speed) async {
    playbackSpeed = speed;
    await _player?.setRate(speed);
    notifyListeners();
  }

  Future<void> _openStream(VideoStreamInfo stream, {Duration? start}) async {
    await _player?.open(Media(stream.url, start: start));
    if (stream.audioUrl != null) {
      await _player?.setAudioTrack(AudioTrack.uri(stream.audioUrl!));
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
    if (currentDownload != null) return; // local files keep no stream state
    final video = currentVideo;
    final stream = currentStream;
    if (video == null || stream == null) return;
    final current = pos ?? position;
    _lastSavedPosition = current;
    unawaited(_storage.savePlaybackState(
      videoId: video.id,
      position: current,
      quality: stream.quality,
      format: stream.format,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifyThrottle?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
