import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'models.dart';
import 'newpipe_service.dart';

/// Keeps Music playback alive while the full player route is closed.
class MusicPlaybackService extends ChangeNotifier {
  final NewPipeService _service = NewPipeService();
  final Player player = Player();

  VideoItem? _song;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  MusicPlaybackService() {
    player.stream.playing.listen((playing) {
      _playing = playing;
      notifyListeners();
    });
  }

  VideoItem? get song => _song;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> play(VideoItem nextSong) async {
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
