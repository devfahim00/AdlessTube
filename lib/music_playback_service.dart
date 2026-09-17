import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_session.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';

/// What the queue does when it reaches the last song.
enum QueueRepeat {
  /// Stop (or fall back to the global autoplay setting).
  off,

  /// Wrap back to the first song — used for favourites so only songs
  /// from that list ever play.
  loop,
}

/// Keeps Music playback in an Android media service with notification controls.
///
/// Purely the Music tab's session: songs, queue, radio, favourites. The
/// video player's audio-only mode borrows the same notification surface
/// (see [audio_session.dart]) without ever touching this service's state
/// — when the user comes back to Music, their queue and song are exactly
/// as they left them.
class MusicPlaybackService extends ChangeNotifier {
  final NewPipeService _service = NewPipeService();
  final StorageService _storage;
  AdlessAudioHandler? _handler;
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

  MusicPlaybackService(this._storage);

  /// Fired whenever music (re)starts playing — from the app or from the
  /// notification controls. The video mini player closes in response so
  /// only one of them ever plays at a time, like the official app.
  void Function()? onPlaybackStarting;

  Future<void> _initialize() {
    return _initializing ??= _startAudioService();
  }

  Future<void> _startAudioService() async {
    try {
      final handler = await sharedAudioHandler();
      _handler = handler;
      handler.onNext = next;
      handler.onPrevious = previous;
      handler.onPlayStarting = () => onPlaybackStarting?.call();
      handler.playbackState.listen((state) {
        // While a video plays audio-only it owns the notification —
        // those events are not this session's and must not flip our
        // playing flag or trigger the queue's auto-advance.
        if (handler.hasVideoAudio) return;
        _playing = state.playing;
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

  Future<AdlessAudioHandler> _getHandler() async {
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
  Future<void> play(
    VideoItem nextSong, {
    List<VideoItem>? queue,
    String? localAudioPath,
  }) async {
    if (queue != null) setQueue(queue, nextSong);
    _loading = true;
    _error = null;
    // Set song early so UI can show title/thumbnail while stream loads.
    _song = nextSong;
    notifyListeners();
    try {
      final handler = await _getHandler();

      // A video may be playing audio-only on the notification surface
      // right now — music takes the surface back before it loads
      // anything (the video stops, keeping its resume spot).
      await handler.stopVideoAudio();

      // If the same song is still loaded, just resume (a stopped
      // player holds no source anymore — that needs a full reload).
      final currentItem = handler.mediaItem.valueOrNull;
      if (currentItem != null &&
          currentItem.id == nextSong.id &&
          handler.hasSource) {
        await handler.play();
        return;
      }

      final Uri source;
      if (localAudioPath != null) {
        source = Uri.file(localAudioPath);
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
      await handler.play();
    } catch (e) {
      _error = e.toString();
      _song = null;
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
    final handler = _handler;
    // While a video plays audio-only it owns the notification surface —
    // the music engine is already idle then, and routing a stop through
    // the handler would tear the video down instead.
    if (handler != null && !handler.hasVideoAudio) await handler.stop();
    _song = null;
    _error = null;
    notifyListeners();
  }
}
