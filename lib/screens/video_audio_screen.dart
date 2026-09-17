import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage_service.dart';
import '../video_playback_service.dart';
import '../widgets.dart';
import 'player_screen.dart';

/// ═══════════════════════ VIDEO NOW PLAYING (AUDIO ONLY) ═══════════════════════
///
/// The dedicated Now Playing surface for the video player's audio-only
/// mode — completely separate from the Music tab's Now Playing. The
/// video's audio keeps playing in the background with notification
/// controls; the Video button returns to the full player at the exact
/// spot the audio reached.
class VideoAudioScreen extends StatefulWidget {
  const VideoAudioScreen({super.key});

  @override
  State<VideoAudioScreen> createState() => _VideoAudioScreenState();
}

class _VideoAudioScreenState extends State<VideoAudioScreen> {
  bool _backToVideo = false;
  bool _stopping = false;
  double _dragValue = -1;

  /// This screen is being REPLACED by the player page — the
  /// replacement pop must not minimize, only a genuine back gesture
  /// shrinks the audio into the mini player.
  bool _replacing = false;

  /// Back to the video: re-enables the video track on the same player
  /// (nothing is reloaded — playback continues at the audio's exact
  /// spot) and reopens the player page on top.
  Future<void> _backToVideoMode() async {
    if (_backToVideo) return;
    final vps = context.read<VideoPlaybackService>();
    final video = vps.currentVideo;
    final download = vps.currentDownload;
    setState(() => _backToVideo = true);
    try {
      await vps.exitAudioOnly();
      if (!mounted || video == null) return;
      // Another video took over while the mode was exiting — its page
      // is already up; don't push ours on top of it.
      if (vps.currentVideo?.id != video.id) return;
      _replacing = true; // our replacement pop is not a minimize
      Navigator.pushReplacement(
        context,
        pushPlayerRoute(
          PlayerScreen(video: video, download: download),
          animationsEnabled:
              context.read<StorageService>().animationsEnabled,
        ),
      );
    } finally {
      if (mounted) setState(() => _backToVideo = false);
    }
  }

  /// Stop the audio and leave — the video's spot is kept, so reopening
  /// it later resumes exactly here.
  Future<void> _stopAndLeave() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    await context.read<VideoPlaybackService>().close();
    if (mounted) Navigator.of(context).pop();
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final vps = context.watch<VideoPlaybackService>();
    final theme = Theme.of(context);
    final video = vps.currentVideo;

    // The session ended underneath us (notification stop) — nothing to show.
    if (video == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<VideoPlaybackService>().currentVideo == null) {
          Navigator.of(context).maybePop();
        }
      });
      return const SizedBox.shrink();
    }

    final maxMs = vps.duration.inMilliseconds > 0
        ? vps.duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = vps.position.inMilliseconds.clamp(0, maxMs.toInt());
    final dragging = _dragValue >= 0;
    final value = dragging ? _dragValue : posMs.toDouble();

    return PopScope(
      // Back keeps the audio playing in the background — it shrinks
      // into the floating mini player (and the notification controls
      // remain), exactly like closing the video player page.
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // Only a genuine user back gesture minimizes — being replaced
        // by the player page keeps the session running untouched.
        if (didPop && !_replacing) vps.minimize();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Now playing')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Artwork — the video thumbnail with an audio badge.
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: VideoThumbnail(
                        videoId: video.id,
                        fallbackUrl: video.thumbnailUrl,
                        width: 250,
                        height: 250,
                        placeholder: Container(
                          width: 250,
                          height: 250,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note, size: 72),
                        ),
                        errorWidget: Container(
                          width: 250,
                          height: 250,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note, size: 72),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.headphones,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  video.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(video.uploader),
                const SizedBox(height: 18),
                // Seek bar
                Slider(
                  value: value.clamp(0.0, maxMs),
                  max: maxMs,
                  onChanged: vps.duration.inMilliseconds > 0
                      ? (ms) => setState(() => _dragValue = ms)
                      : null,
                  onChangeEnd: vps.duration.inMilliseconds > 0
                      ? (ms) {
                          setState(() => _dragValue = -1);
                          vps.seekTo(Duration(milliseconds: ms.round()));
                        }
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(vps.position)),
                    Text(_formatTime(vps.duration)),
                  ],
                ),
                const SizedBox(height: 8),
                // Main controls: -10s / play-pause / +10s
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: () =>
                          vps.seekBy(const Duration(seconds: -10)),
                      icon: const Icon(Icons.replay_10),
                      iconSize: 34,
                      tooltip: 'Back 10 seconds',
                    ),
                    IconButton.filled(
                      iconSize: 46,
                      onPressed: vps.togglePlayPause,
                      icon: Icon(
                        vps.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      onPressed: () => vps.seekBy(const Duration(seconds: 10)),
                      icon: const Icon(Icons.forward_10),
                      iconSize: 34,
                      tooltip: 'Forward 10 seconds',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Secondary actions.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionIcon(
                      icon: Icons.ondemand_video_outlined,
                      label: 'Video',
                      loading: _backToVideo,
                      onTap: _backToVideoMode,
                    ),
                    _actionIcon(
                      icon: Icons.stop,
                      label: 'Stop',
                      loading: _stopping,
                      onTap: _stopAndLeave,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: loading ? null : onTap,
          icon: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                )
              : Icon(icon, size: 24),
          tooltip: label,
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
