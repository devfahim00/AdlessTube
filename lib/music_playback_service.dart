import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';

class _AdlessAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;

  _AdlessAudioHandler() {
    // Broadcast state on every playback event
    _player.playbackEventStream.listen((_) => _broadcastState());

    // Keep MediaItem.duration always up-to-date
    // (critical for Android notification progress bar + seek)
    _player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null && duration != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
      _broadcastState();
    });

    // Push position updates while playing so notification seek bar stays live
    _player.positionStream.listen((_) {
      if (_player.playing) _broadcastState();
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get duration => _player.duration ?? Duration.zero;
  Duration get position => _player.position;

  /// Whether the player still holds a loaded source — false after
  /// stop(), where a bare play() would silently do nothing.
  bool get hasSource => _player.processingState != ProcessingState.idle;

  Future<void> load(MediaItem item, Uri source) async {
    mediaItem.add(item);
    await _player.setAudioSource(AudioSource.uri(source, tag: item));

    // Set duration immediately if already known
    final d = _player.duration;
    if (d != null) {
      mediaItem.add(item.copyWith(duration: d));
    }
    _broadcastState();
  }

  /// Fired whenever the handler (re)starts audio — used to make the
  /// video mini player yield so two things never play at once.
  void Function()? onPlayStarting;

  @override
  Future<void> play() {
    onPlayStarting?.call();
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPrevious?.call();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'favorite') {
      customEvent.add({'type': 'favorite'});
    }
  }

  void _broadcastState() {
    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.custom(
            androidIcon: 'drawable/ic_action_favorite',
            label: 'Favourite',
            name: 'favorite',
          ),
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        updateTime: DateTime.now(),
      ),
    );
  }
}

/// What the queue does when it reaches the last song.
enum QueueRepeat {
  /// Stop (or fall back to the global autoplay setting).
  off,

  /// Wrap back to the first song — used for favourites so only songs
  /// from that list ever play.
  loop,
}

/// Keeps Music playback in an Android media service with notification controls.
class MusicPlaybackService extends ChangeNotifier with WidgetsBindingObserver {
  final NewPipeService _service = NewPipeService();
  final StorageService _storage;
  _AdlessAudioHandler? _handler;
  Future<void>? _initializing;

  VideoItem? _song;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  List<VideoItem> _queue = [];
  int _queueIndex = -1;
  bool _handlingCompletion = false;
  QueueRepeat _repeat = QueueRepeat.off;
  bool _radio = false;

  // ─────────── Video handoff: resume-spot sync ───────────
  //
  // When a video is handed off to audio-only mode, its saved resume
  // position keeps following the music playback: close the app
  // mid-song and reopening that video (or just the app) lands on the
  // exact spot the audio reached — never back at the handoff spot.
  String? _syncVideoId;
  String? _syncQuality;
  String? _syncFormat;
  Duration _lastSyncedPosition = Duration.zero;
  Duration _lastSyncedDuration = Duration.zero;
  Timer? _syncTimer;

  MusicPlaybackService(this._storage) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Fired whenever music (re)starts playing — from the app or from the
  /// notification controls. The video mini player closes in response so
  /// only one of them ever plays at a time, like the official app.
  void Function()? onPlaybackStarting;

  Future<void> _initialize() {
    return _initializing ??= _startAudioService();
  }

  Future<void> _startAudioService() async {
    _AdlessAudioHandler? localHandler;
    try {
      await AudioService.init(
        builder: () {
          localHandler = _AdlessAudioHandler();
          return localHandler!;
        },
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.devfahim00.tube.music',
          androidNotificationChannelName: 'AdlessTube Music',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      ).timeout(const Duration(seconds: 12));
      final handler = localHandler;
      if (handler == null) throw StateError('Music service could not start.');
      _handler = handler;
      handler.onNext = next;
      handler.onPrevious = previous;
      handler.onPlayStarting = () => onPlaybackStarting?.call();
      handler.playbackState.listen((state) {
        final wasPlaying = _playing;
        _playing = state.playing;
        // Pausing a handed-off audio pins the video's spot right
        // away — the periodic sync only saves while playing.
        if (wasPlaying && !_playing && _syncVideoId != null) {
          _pinSyncedSpot();
        }
        if (state.processingState == AudioProcessingState.completed &&
            (_storage.musicAutoplay || _radio) &&
            !_handlingCompletion) {
          _handlingCompletion = true;
          unawaited(next().whenComplete(() => _handlingCompletion = false));
        }
        notifyListeners();
      });
      handler.customEvent.listen((event) {
        if (event is Map && event['type'] == 'favorite' && _song != null) {
          unawaited(_storage.toggleLikedSong(_song!));
        }
      });
    } catch (e) {
      _error = 'Music service could not start: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<_AdlessAudioHandler> _getHandler() async {
    await _initialize();
    final handler = _handler;
    if (handler == null) throw StateError('Music service is unavailable.');
    return handler;
  }

  VideoItem? get song => _song;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get error => _error;
  bool get isRadioActive => _radio;
  QueueRepeat get repeatMode => _repeat;
  Stream<Duration> get positionStream =>
      _handler?.positionStream ?? Stream.value(Duration.zero);
  Stream<Duration?> get durationStream =>
      _handler?.durationStream ?? Stream.value(null);
  Duration get duration => _handler?.duration ?? Duration.zero;
  bool get canGoNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1;
  bool get canGoPrevious => _queueIndex > 0;
  int get queueLength => _queue.length;
  int get queueIndex => _queueIndex;

  Future<void> playOrPause() async {
    final handler = await _getHandler();
    await (_playing ? handler.pause() : handler.play());
  }

  Future<void> seek(Duration position) async {
    final handler = await _getHandler();
    await handler.seek(position);
  }

  void setQueue(
    List<VideoItem> songs,
    VideoItem selected, {
    QueueRepeat repeat = QueueRepeat.off,
    bool radio = false,
  }) {
    _queue = songs.where((song) => !song.isLive && !song.isShort).toList();
    _queueIndex = _queue.indexWhere((song) => song.id == selected.id);
    if (_queueIndex < 0) {
      _queue = [selected, ..._queue];
      _queueIndex = 0;
    }
    _repeat = repeat;
    _radio = radio;
  }

  /// Plays [nextSong] through the background audio service.
  ///
  /// The extra parameters serve the audio-only handoff from the
  /// video player: [audioUrl] reuses the exact audio stream the
  /// video was playing (keeps a chosen dub, skips a re-extraction),
  /// [startAt] continues from the video's current spot, and
  /// [fromVideo] keeps the video's resume position in sync while the
  /// audio plays. Returns false when the audio could not start.
  Future<bool> play(
    VideoItem nextSong, {
    List<VideoItem>? queue,
    String? localAudioPath,
    String? audioUrl,
    Duration? startAt,
    bool fromVideo = false,
    String? videoQuality,
    String? videoFormat,
  }) async {
    if (queue != null) setQueue(queue, nextSong);
    _loading = true;
    _error = null;
    // Set song early so UI can show title/thumbnail while stream loads.
    _song = nextSong;
    notifyListeners();
    try {
      // A new song ends any previous video handoff's sync — pin that
      // video's spot first so its progress is never lost.
      await _stopVideoResumeSync();
      final handler = await _getHandler();

      // If the same song is still loaded, just resume (a stopped
      // player holds no source anymore — that needs a full reload).
      final currentItem = handler.mediaItem.valueOrNull;
      if (currentItem != null &&
          currentItem.id == nextSong.id &&
          handler.hasSource) {
        if (startAt != null && startAt > const Duration(seconds: 1)) {
          await handler.seek(startAt);
        }
        await handler.play();
        if (fromVideo) {
          _startVideoResumeSync(
            nextSong.id,
            quality: videoQuality,
            format: videoFormat,
          );
        }
        return true;
      }

      final Uri source;
      if (localAudioPath != null) {
        source = Uri.file(localAudioPath);
      } else if (audioUrl != null && audioUrl.isNotEmpty) {
        source = Uri.parse(audioUrl);
      } else {
        final audio = await _service.getBestAudioStream(nextSong.url);
        if (audio == null) {
          throw Exception('No audio stream found for this song.');
        }
        source = Uri.parse(audio.url);
      }
      await handler.load(
        MediaItem(
          id: nextSong.id,
          title: nextSong.title,
          artist: nextSong.uploader,
          artUri: nextSong.thumbnailUrl.isEmpty
              ? null
              : Uri.tryParse(nextSong.thumbnailUrl),
        ),
        source,
      );
      if (startAt != null && startAt > const Duration(seconds: 1)) {
        await handler.seek(startAt);
      }
      await handler.play();
      if (fromVideo) {
        _startVideoResumeSync(
          nextSong.id,
          quality: videoQuality,
          format: videoFormat,
        );
      }
      return true;
    } catch (e) {
      _error = e.toString();
      _song = null;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> next() async {
    if (canGoNext) {
      _queueIndex++;
      await play(_queue[_queueIndex]);
    } else if (_repeat == QueueRepeat.loop && _queue.isNotEmpty) {
      // Favourites-style queues wrap around and never pull in outside songs.
      _queueIndex = 0;
      await play(_queue.first);
    } else if (_radio || _storage.musicAutoplay) {
      await _playRelated();
    }
  }

  Future<void> previous() async {
    if (!canGoPrevious) return;
    _queueIndex--;
    await play(_queue[_queueIndex]);
  }

  /// Starts an endless radio: similar songs keep playing one after another.
  /// The current song keeps playing; related songs become the upcoming queue.
  Future<void> startRadio() async {
    final current = _song;
    _radio = true;
    _repeat = QueueRepeat.off;
    notifyListeners();
    if (current == null) return;
    try {
      final related = await _service.getRelatedVideos(current.url);
      final songs =
          related.where((song) => !song.isLive && !song.isShort).toList();
      if (songs.isEmpty) return;
      _queue = [current, ...songs];
      _queueIndex = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopRadio() async {
    _radio = false;
    notifyListeners();
  }

  Future<void> _playRelated() async {
    final current = _song;
    if (current == null) return;
    try {
      final related = await _service.getRelatedVideos(current.url);
      final songs =
          related.where((song) => !song.isLive && !song.isShort).toList();
      if (songs.isEmpty) return;
      _queue = songs;
      _queueIndex = 0;
      await play(_queue.first);
    } catch (_) {}
  }

  Future<void> stop() async {
    await _stopVideoResumeSync();
    final handler = _handler;
    if (handler != null) await handler.stop();
    _song = null;
    _error = null;
    notifyListeners();
  }

  // ─────────── Video handoff: resume-spot sync ───────────

  /// While a handed-off video plays as audio, checkpoint its resume
  /// spot every few seconds — the same cadence the video player
  /// itself uses. A stopped or still-loading player reports zero and
  /// must never wipe a good resume spot.
  void _startVideoResumeSync(
    String videoId, {
    String? quality,
    String? format,
  }) {
    _syncTimer?.cancel();
    _syncVideoId = videoId;
    _syncQuality = quality;
    _syncFormat = format;
    _lastSyncedPosition = Duration.zero;
    _lastSyncedDuration = Duration.zero;
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final handler = _handler;
      final id = _syncVideoId;
      if (handler == null || id == null || !_playing) return;
      _pinSyncedSpot();
    });
  }

  /// Saves the handed-off video's current spot right now (periodic
  /// tick, pause). Zero positions from stopped or still-loading
  /// players are ignored so a good resume spot is never wiped.
  void _pinSyncedSpot() {
    final handler = _handler;
    final id = _syncVideoId;
    if (handler == null || id == null) return;
    final pos = handler.position;
    final dur = handler.duration;
    if (pos.inMilliseconds <= 0 || dur.inMilliseconds <= 0) return;
    _lastSyncedPosition = pos;
    _lastSyncedDuration = dur;
    unawaited(_storage.savePlaybackState(
      videoId: id,
      position: pos,
      duration: dur,
      quality: _syncQuality,
      format: _syncFormat,
    ));
  }

  /// Ends the sync. With [save], pins the last known spot one final
  /// time so stopping, skipping or switching songs never loses the
  /// video's progress.
  Future<void> _stopVideoResumeSync({bool save = true}) async {
    final timer = _syncTimer;
    _syncTimer = null;
    timer?.cancel();
    final id = _syncVideoId;
    final quality = _syncQuality;
    final format = _syncFormat;
    final position = _lastSyncedPosition;
    final duration = _lastSyncedDuration;
    _syncVideoId = null;
    _syncQuality = null;
    _syncFormat = null;
    _lastSyncedPosition = Duration.zero;
    _lastSyncedDuration = Duration.zero;
    if (id == null || !save) return;
    if (position.inMilliseconds > 0 && duration.inMilliseconds > 0) {
      await _storage.savePlaybackState(
        videoId: id,
        position: position,
        duration: duration,
        quality: quality,
        format: format,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // The OS can reap the process at any moment after this — pin a
      // handed-off video's spot and push it to disk before it does.
      if (_syncVideoId != null) {
        unawaited(
          _stopVideoResumeSync().then((_) => _storage.flushPlayback()),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    unawaited(_stopVideoResumeSync());
    super.dispose();
  }
}
