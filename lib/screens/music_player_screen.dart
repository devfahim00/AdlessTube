import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../download_service.dart';
import '../models.dart';
import '../music_playback_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'player_screen.dart';

/// ═══════════════════════ NOW PLAYING ═══════════════════════
class MusicPlayerScreen extends StatefulWidget {
  final VideoItem song;

  /// Whether initState should start playback. The audio-only handoff
  /// from the video player passes false — the audio is already playing
  /// at the video's exact position when this screen opens.
  final bool autoPlay;

  const MusicPlayerScreen({super.key, required this.song, this.autoPlay = true});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  late final StorageService _storage;
  bool _leaving = false;
  bool _switchingToVideo = false;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    if (widget.autoPlay) {
      unawaited(context.read<MusicPlaybackService>().play(widget.song));
    }
  }

  /// Second half of the audio-only toggle: hand the now playing audio
  /// back to the video player. The video reopens and resumes from the
  /// audio's exact position — a completed local video download plays
  /// instead of the network stream when one exists.
  Future<void> _switchBackToVideo() async {
    if (_switchingToVideo) return;
    final music = context.read<MusicPlaybackService>();
    final song = music.song ?? widget.song;
    setState(() => _switchingToVideo = true);
    try {
      // A completed local video copy plays offline — a muxed
      // (video+audio) download is preferred when several exist.
      DownloadItem? download;
      for (final item in context.read<DownloadService>().getAll()) {
        if (item.videoId == song.id &&
            item.isCompleted &&
            item.videoPath != null) {
          download = item;
          if (item.type == DownloadType.videoAudio) break;
        }
      }
      // Pins the video's resume spot at the audio's live position,
      // then stops the music (notification controls included).
      await music.switchBackToVideo();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        pushPlayerRoute(
          PlayerScreen(video: song, download: download),
          animationsEnabled: _storage.animationsEnabled,
        ),
      );
    } finally {
      if (mounted) setState(() => _switchingToVideo = false);
    }
  }

  Future<void> _stopAndLeave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await context.read<MusicPlaybackService>().stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleRadio() async {
    final music = context.read<MusicPlaybackService>();
    if (music.isRadioActive) {
      await music.stopRadio();
    } else {
      await music.startRadio();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Radio started — similar songs will keep playing'),
          ),
        );
      }
    }
  }

  /// Tap handler for the download action — mirrors the live state:
  /// in-flight → status snackbar, completed → remove sheet, else → start.
  Future<void> _onDownloadTapped(VideoItem song) async {
    final downloads = context.read<DownloadService>();
    final messenger = ScaffoldMessenger.of(context);
    final active = downloads.activeFor(song.id);
    if (active != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Downloading — manage it from Library ▸ Downloads'),
        ),
      );
      return;
    }
    if (downloads.isDownloaded(song.id)) {
      final item = downloads.playableFor(song.id);
      if (item != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove download?'),
            content: Text(
                '"${song.title}" will be deleted from this device.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await context.read<DownloadService>().delete(item);
        }
      }
      return;
    }
    await downloads.startDownload(
      video: song,
      type: DownloadType.music,
      quality: 'Best',
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Downloading music — see Library ▸ Downloads'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final music = context.watch<MusicPlaybackService>();
    // Watching downloads keeps the action reactive to progress ticks.
    context.watch<DownloadService>();
    final currentSong = music.song ?? widget.song;
    final liked = storage.isSongLiked(currentSong.id);
    final navigator = Navigator.of(context);

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_leaving) {
          setState(() => _leaving = true);
          if (!music.isPlaying) await music.stop();
          if (mounted) navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Now playing')),
        body: music.error != null
            ? ErrorView(
                message: music.error!,
                onRetry: () => music.play(widget.song),
              )
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Album art + optional loading indicator
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: currentSong.thumbnailUrl.isEmpty
                                ? Container(
                                    width: 250,
                                    height: 250,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(Icons.music_note,
                                        size: 72),
                                  )
                                : VideoThumbnail(
                                    videoId: currentSong.id,
                                    fallbackUrl: currentSong.thumbnailUrl,
                                    width: 250,
                                    height: 250,
                                    placeholder: Container(
                                      width: 250,
                                      height: 250,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    errorWidget: Container(
                                      width: 250,
                                      height: 250,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: const Icon(Icons.music_note,
                                          size: 72),
                                    ),
                                  ),
                          ),
                          if (music.isLoading && !music.isPlaying)
                            const CircularProgressIndicator(),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        currentSong.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(currentSong.uploader),
                      const SizedBox(height: 18),
                      // Seek bar – uses both position + duration streams
                      StreamBuilder<Duration>(
                        stream: music.positionStream,
                        builder: (context, posSnap) {
                          return StreamBuilder<Duration?>(
                            stream: music.durationStream,
                            builder: (context, durSnap) {
                              final position = posSnap.data ?? Duration.zero;
                              final duration =
                                  durSnap.data ?? music.duration;
                              final max = duration.inMilliseconds > 0
                                  ? duration.inMilliseconds.toDouble()
                                  : 1.0;
                              final value = position.inMilliseconds
                                  .clamp(0, max.toInt())
                                  .toDouble();
                              return Column(
                                children: [
                                  Slider(
                                    value: value,
                                    max: max,
                                    onChanged: duration.inMilliseconds > 0
                                        ? (ms) => music.seek(
                                              Duration(
                                                  milliseconds: ms.round()),
                                            )
                                          : null,
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatMusicTime(position)),
                                      Text(_formatMusicTime(duration)),
                                    ],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Main controls — equal gaps between prev / play / next.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed:
                                music.canGoPrevious ? music.previous : null,
                            icon: const Icon(Icons.skip_previous),
                            iconSize: 34,
                            tooltip: 'Previous song',
                          ),
                          IconButton.filled(
                            iconSize: 46,
                            onPressed: music.playOrPause,
                            icon: Icon(
                              music.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                          ),
                          IconButton(
                            onPressed: music.canGoNext ||
                                    music.isRadioActive ||
                                    _storage.musicAutoplay
                                ? music.next
                                : null,
                            icon: const Icon(Icons.skip_next),
                            iconSize: 34,
                            tooltip: 'Next song',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Secondary actions.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Back to video mode — the second tap of the
                          // audio-only toggle: the video resumes from
                          // the now playing timestamp.
                          _actionIcon(
                            icon: Icons.ondemand_video_outlined,
                            label: 'Video',
                            loading: _switchingToVideo,
                            onTap: _switchBackToVideo,
                          ),
                          _actionIcon(
                            icon: liked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: liked ? 'Liked' : 'Like',
                            color: liked
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            onTap: () =>
                                _storage.toggleLikedSong(currentSong),
                          ),
                          _MusicDownloadAction(
                            song: currentSong,
                            onTap: () => _onDownloadTapped(currentSong),
                          ),
                          _actionIcon(
                            icon: music.isRadioActive
                                ? Icons.all_inclusive
                                : Icons.queue_music,
                            label: music.isRadioActive
                                ? 'Radio on'
                                : 'Start radio',
                            color: music.isRadioActive
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            onTap: _toggleRadio,
                          ),
                          _actionIcon(
                            icon: Icons.stop,
                            label: 'Stop',
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
    Color? color,
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
          color: color,
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

/// Download action that mirrors the live download state: a progress ring
/// with the percentage while downloading, a red check once the song is on
/// disk, and the plain download action otherwise.
class _MusicDownloadAction extends StatelessWidget {
  final VideoItem song;
  final VoidCallback onTap;

  const _MusicDownloadAction({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final active = downloads.activeFor(song.id);
    final done = active == null && downloads.isDownloaded(song.id);

    final label = active != null
        ? (active.progress > 0
            ? '${(active.progress * 100).round()}%'
            : 'Downloading')
        : done
            ? 'Downloaded'
            : 'Download';
    final color = done ? Theme.of(context).colorScheme.primary : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          color: color,
          tooltip: label,
          icon: active != null
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: active.progress > 0 ? active.progress : null,
                    strokeWidth: 2.6,
                  ),
                )
              : Icon(
                  done ? Icons.download_done : Icons.download_outlined,
                  size: 24,
                  color: color,
                ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}

String _formatMusicTime(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
