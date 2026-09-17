import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// ═══════════════════════ AUDIO SESSION ═══════════════════════
///
/// The app's single media-notification surface. Android allows exactly
/// one media session per app (audio_service is a singleton), so the
/// Music tab's just_audio player and the video player's audio-only
/// mode share this handler — never both at once:
///
/// * normally the music engine (just_audio) drives the notification,
/// * while a video plays audio-only, a [VideoAudioController] takes
///   over: notification controls route to the video player (mpv) and
///   the state shown in the notification is pushed from mpv.
///
/// The music session keeps its own queue and song state untouched
/// throughout — it is simply stopped while the surface is borrowed.

/// The video side of the shared notification surface. Built by the
/// video playback service whenever a video switches to audio-only.
class VideoAudioController {
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(Duration position) seek;

  /// Notification stop: tears the audio-only video down completely
  /// (its resume spot is kept, so it reopens where it stopped).
  final Future<void> Function() stop;

  const VideoAudioController({
    required this.play,
    required this.pause,
    required this.seek,
    required this.stop,
  });
}

/// The one audio handler — the notification and lock-screen controls
/// live here no matter which engine is playing.
class AdlessAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  /// The music engine. Stopped whenever a video borrows the surface.
  final AudioPlayer player = AudioPlayer();

  /// Music-session hooks — wired by [MusicPlaybackService].
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;

  /// Fired whenever the music engine (re)starts audio — used to make
  /// the video mini player yield so two things never play at once.
  void Function()? onPlayStarting;

  /// The video audio-only session, while it owns the surface.
  VideoAudioController? _videoAudio;
  bool get hasVideoAudio => _videoAudio != null;

  AdlessAudioHandler() {
    // Broadcast music state on every playback event — but never while
    // a video's audio-only session owns the surface.
    player.playbackEventStream.listen((_) => _broadcastMusicState());

    // Keep MediaItem.duration always up-to-date
    // (critical for Android notification progress bar + seek)
    player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null &&
          duration != null &&
          current.duration != duration &&
          _videoAudio == null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
      _broadcastMusicState();
    });

    // Push position updates while playing so notification seek bar stays live
    player.positionStream.listen((_) {
      if (player.playing) _broadcastMusicState();
    });
  }

  /// Whether the music engine still holds a loaded source — false
  /// after stop(), where a bare play() would silently do nothing.
  bool get hasSource => player.processingState != ProcessingState.idle;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Duration get duration => player.duration ?? Duration.zero;

  /// Loads a song into the music engine and takes over the surface.
  Future<void> load(MediaItem item, Uri source) async {
    mediaItem.add(item);
    await player.setAudioSource(AudioSource.uri(source, tag: item));

    // Set duration immediately if already known
    final d = player.duration;
    if (d != null) {
      mediaItem.add(item.copyWith(duration: d));
    }
    _broadcastMusicState();
  }

  // ─────────── Control routing ───────────

  @override
  Future<void> play() {
    final video = _videoAudio;
    if (video != null) return video.play();
    onPlayStarting?.call();
    return player.play();
  }

  @override
  Future<void> pause() {
    final video = _videoAudio;
    if (video != null) return video.pause();
    return player.pause();
  }

  @override
  Future<void> seek(Duration position) {
    final video = _videoAudio;
    if (video != null) return video.seek(position);
    return player.seek(position);
  }

  @override
  Future<void> stop() async {
    final video = _videoAudio;
    if (video != null) {
      // Stop from the notification while a video plays audio-only:
      // the video side clears the bridge and tears itself down, then
      // the idle broadcast dismisses the notification.
      _videoAudio = null;
      await video.stop();
      await super.stop();
      return;
    }
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_videoAudio != null) return; // single video — no queue
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_videoAudio != null) return; // single video — no queue
    await onPrevious?.call();
  }

  @override
  Future<void> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (_videoAudio != null) return; // likes belong to songs
    if (name == 'favorite') {
      customEvent.add({'type': 'favorite'});
    }
  }

  // ─────────── Video audio-only session ───────────

  /// Hands the notification surface to a video playing audio-only.
  void attachVideoAudio(VideoAudioController controller) {
    _videoAudio = controller;
  }

  /// Shows [item] (title, channel, artwork) for the video audio.
  void setVideoMediaItem(MediaItem item) {
    if (_videoAudio == null) return;
    mediaItem.add(item);
  }

  /// Keeps the video MediaItem's duration in sync (progress bar).
  void updateVideoDuration(Duration duration) {
    if (_videoAudio == null) return;
    final current = mediaItem.valueOrNull;
    if (current != null && current.duration != duration) {
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  /// Pushes the video player's live state into the notification.
  void pushVideoState({
    required bool playing,
    required Duration position,
    required Duration buffered,
    required AudioProcessingState processing,
  }) {
    if (_videoAudio == null) return;
    playbackState.add(
      PlaybackState(
        controls: [
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: processing,
        playing: playing,
        updatePosition: position,
        bufferedPosition: buffered,
        updateTime: DateTime.now(),
      ),
    );
  }

  /// Releases the surface back from a video audio-only session and
  /// dismisses the notification. Called by the video player when the
  /// user returns to video mode or the video ends.
  Future<void> detachVideoAudio() async {
    _videoAudio = null;
    // Same idle broadcast the (long-working) music stop uses.
    await super.stop();
  }

  /// Music wants the surface back: if a video is currently playing
  /// audio-only, it stops now (its resume spot is kept). Called at
  /// the top of the music play path.
  Future<void> stopVideoAudio() async {
    final video = _videoAudio;
    if (video == null) return;
    _videoAudio = null;
    // Dismiss the video notification immediately so the song's
    // MediaItem never fights the video's for the slot.
    playbackState.add(PlaybackState(
      controls: const [],
      processingState: AudioProcessingState.idle,
    ));
    await video.stop();
  }

  // ─────────── Music engine state ───────────

  void _broadcastMusicState() {
    // A video audio-only session owns the surface — its pushed state
    // must not be clobbered by the (stopped) music engine.
    if (_videoAudio != null) return;
    final processingState = switch (player.processingState) {
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
          player.playing ? MediaControl.pause : MediaControl.play,
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
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        updateTime: DateTime.now(),
      ),
    );
  }
}

/// The singleton handler — both engines get the exact same instance.
Future<AdlessAudioHandler>? _sharedInit;

Future<AdlessAudioHandler> sharedAudioHandler() {
  return _sharedInit ??= _startAudioService();
}

Future<AdlessAudioHandler> _startAudioService() async {
  AdlessAudioHandler? localHandler;
  try {
    await AudioService.init(
      builder: () {
        localHandler = AdlessAudioHandler();
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
    if (handler == null) throw StateError('Audio service could not start.');
    return handler;
  } catch (e) {
    _sharedInit = null; // a later call may retry
    rethrow;
  }
}
