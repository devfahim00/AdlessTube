import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../download_service.dart';
import '../models.dart';
import '../music_playback_service.dart';
import '../storage_service.dart';
import '../widgets.dart';

/// ═══════════════════════ NOW PLAYING ═══════════════════════
class MusicPlayerScreen extends StatefulWidget {
  final VideoItem song;

  const MusicPlayerScreen({super.key, required this.song});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  late final StorageService _storage;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    unawaited(context.read<MusicPlaybackService>().play(widget.song));
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

  Future<void> _downloadCurrent() async {
    final music = context.read<MusicPlaybackService>();
    final song = music.song ?? widget.song;
    final downloads = context.read<DownloadService>();
    final messenger = ScaffoldMessenger.of(context);
    if (downloads.isDownloaded(song.id)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Already downloaded')),
      );
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
                                : Image.network(
                                    currentSong.thumbnailUrl,
                                    width: 250,
                                    height: 250,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
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
                          _actionIcon(
                            icon: liked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: liked ? 'Liked' : 'Like',
                            color: liked ? Colors.red : null,
                            onTap: () =>
                                _storage.toggleLikedSong(currentSong),
                          ),
                          _actionIcon(
                            icon: Icons.download_outlined,
                            label: 'Download',
                            onTap: _downloadCurrent,
                          ),
                          _actionIcon(
                            icon: music.isRadioActive
                                ? Icons.all_inclusive
                                : Icons.queue_music,
                            label: music.isRadioActive
                                ? 'Radio on'
                                : 'Start radio',
                            color:
                                music.isRadioActive ? Colors.red : null,
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
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 24),
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

String _formatMusicTime(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
