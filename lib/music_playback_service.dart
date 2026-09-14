import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';

/// Keeps Music playback alive while the full player route is closed.
class MusicPlaybackService extends ChangeNotifier {
  final NewPipeService _service = NewPipeService();
  final StorageService _storage;
  final Player player = Player();

  VideoItem? _song;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  List<VideoItem> _queue = [];
  int _queueIndex = -1;

  MusicPlaybackService(this._storage) {
    player.stream.playing.listen((playing) {
      _playing = playing;
      notifyListeners();
    });
    player.stream.completed.listen((completed) {
      if (completed && _storage.musicAutoplay) unawaited(next());
    });
  }

  VideoItem? get song => _song;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get error => _error;
  bool get canGoNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1;
  bool get canGoPrevious => _queueIndex > 0;

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
      await player.play();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final audio = await _service.getBestAudioStream(nextSong.url);
      if (audio == null) throw Exception('No audio stream found for this song.');
      _song = nextSong;
      await player.open(Media(audio.url));
      await player.play();
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
      return;
    }
    if (_storage.musicAutoplay) await _playRelated();
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
    await player.stop();
    _song = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(player.dispose());
    super.dispose();
  }
}
