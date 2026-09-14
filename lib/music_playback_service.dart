import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
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
    _player.playbackEventStream.listen((_) => _broadcastState());
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get duration => _player.duration ?? Duration.zero;

  Future<void> load(MediaItem item, Uri source) async {
    mediaItem.add(item);
    await _player.setAudioSource(AudioSource.uri(source, tag: item));
  }

  @override
  Future<void> play() => _player.play();

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
    if (name == 'favorite') customEvent.add({'type': 'favorite'});
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
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }
}

/// Keeps Music playback in an Android media service with notification controls.
class MusicPlaybackService extends ChangeNotifier {
  final NewPipeService _service = NewPipeService();
  final StorageService _storage;
  final _AdlessAudioHandler _handler;

  VideoItem? _song;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  List<VideoItem> _queue = [];
  int _queueIndex = -1;
  bool _handlingCompletion = false;

  MusicPlaybackService._(this._storage, this._handler) {
    _handler.onNext = next;
    _handler.onPrevious = previous;
    _handler.playbackState.listen((state) {
      _playing = state.playing;
      if (state.processingState == AudioProcessingState.completed &&
          _storage.musicAutoplay &&
          !_handlingCompletion) {
        _handlingCompletion = true;
        unawaited(next().whenComplete(() => _handlingCompletion = false));
      }
      notifyListeners();
    });
    _handler.customEvent.listen((event) {
      if (event is Map && event['type'] == 'favorite' && _song != null) {
        unawaited(_storage.toggleLikedSong(_song!));
      }
    });
  }

  static Future<MusicPlaybackService> create(StorageService storage) async {
    _AdlessAudioHandler? localHandler;
    await AudioService.init(
      builder: () {
        localHandler = _AdlessAudioHandler();
        return localHandler!;
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.devfahim00.tube.music',
        androidNotificationChannelName: 'AdlessTube Music',
        androidNotificationOngoing: true,
      ),
    );
    return MusicPlaybackService._(storage, localHandler!);
  }

  VideoItem? get song => _song;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get error => _error;
  Stream<Duration> get positionStream => _handler.positionStream;
  Duration get duration => _handler.duration;
  bool get canGoNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1;
  bool get canGoPrevious => _queueIndex > 0;

  Future<void> playOrPause() => _playing ? _handler.pause() : _handler.play();
  Future<void> seek(Duration position) => _handler.seek(position);

  void setQueue(List<VideoItem> songs, VideoItem selected) {
    _queue = songs.where((song) => !song.isLive && !song.isShort).toList();
    _queueIndex = _queue.indexWhere((song) => song.id == selected.id);
    if (_queueIndex < 0) {
      _queue = [selected, ..._queue];
      _queueIndex = 0;
    }
  }

  Future<void> play(VideoItem nextSong, {List<VideoItem>? queue}) async {
    if (queue != null) setQueue(queue, nextSong);
    if (_song?.id == nextSong.id && _error == null) {
      await _handler.play();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final audio = await _service.getBestAudioStream(nextSong.url);
      if (audio == null) throw Exception('No audio stream found for this song.');
      _song = nextSong;
      await _handler.load(
        MediaItem(
          id: nextSong.id,
          title: nextSong.title,
          artist: nextSong.uploader,
          artUri: nextSong.thumbnailUrl.isEmpty
              ? null
              : Uri.tryParse(nextSong.thumbnailUrl),
        ),
        Uri.parse(audio.url),
      );
      await _handler.play();
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
    } else if (_storage.musicAutoplay) {
      await _playRelated();
    }
  }

  Future<void> previous() async {
    if (!canGoPrevious) return;
    _queueIndex--;
    await play(_queue[_queueIndex]);
  }

  Future<void> _playRelated() async {
    final current = _song;
    if (current == null) return;
    try {
      final related = await _service.getRelatedVideos(current.url);
      final songs = related.where((song) => !song.isLive && !song.isShort).toList();
      if (songs.isEmpty) return;
      _queue = songs;
      _queueIndex = 0;
      await play(_queue.first);
    } catch (_) {}
  }

  Future<void> stop() async {
    await _handler.stop();
    _song = null;
    _error = null;
    notifyListeners();
  }
}
