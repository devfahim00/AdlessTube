import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../download_service.dart';
import '../models.dart';
import '../music_playback_service.dart';
import 'music_player_screen.dart';
import 'player_screen.dart';

/// ═══════════════════════ DOWNLOADS ═══════════════════════
///
/// Every downloaded video and song in one place, grouped by category.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: const DownloadsList(bottomPadding: 24),
    );
  }
}

/// Shared downloads list — embedded in the Library tab and the standalone
/// Downloads screen. Filter chips switch between Videos and Music.
class DownloadsList extends StatefulWidget {
  final double bottomPadding;

  const DownloadsList({super.key, this.bottomPadding = 24});

  @override
  State<DownloadsList> createState() => _DownloadsListState();
}

class _DownloadsListState extends State<DownloadsList> {
  String _filter = 'All'; // All | Videos | Music

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    var items = downloads.getAll();
    if (_filter == 'Videos') {
      items = items
          .where((item) =>
              item.type == DownloadType.videoAudio ||
              item.type == DownloadType.videoOnly)
          .toList();
    } else if (_filter == 'Music') {
      items = items.where((item) => item.isMusic).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final filter in const ['All', 'Videos', 'Music'])
                _filterChip(filter),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _filter == 'All'
                          ? 'No downloads yet.\nUse the Download button on any video or song.'
                          : 'Nothing here yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: widget.bottomPadding),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _DownloadTile(item: items[index]),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.red : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadItem item;

  const _DownloadTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.isDownloading
        ? null
        : item.isFailed
            ? const Text('Download failed', style: TextStyle(color: Colors.red))
            : Text(_subtitle(item),
                style: TextStyle(color: Colors.grey[500], fontSize: 12));

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: item.thumbnailUrl.isEmpty
            ? Container(
                width: item.isMusic ? 52 : 100,
                height: 56,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                    item.isMusic ? Icons.music_note : Icons.videocam),
              )
            : Image.network(
                item.thumbnailUrl,
                width: item.isMusic ? 52 : 100,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: item.isMusic ? 52 : 100,
                  height: 56,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                      item.isMusic ? Icons.music_note : Icons.videocam),
                ),
              ),
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.isDownloading
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: item.totalBytes > 0 ? item.progress : null,
                ),
                const SizedBox(height: 4),
                Text(
                  item.totalBytes > 0
                      ? '${(item.progress * 100).toStringAsFixed(0)}% • ${_formatBytes(item.receivedBytes)} of ${_formatBytes(item.totalBytes)}'
                      : 'Downloading… ${_formatBytes(item.receivedBytes)}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            )
          : subtitle,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          final downloads = context.read<DownloadService>();
          if (value == 'delete') downloads.delete(item);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20),
                SizedBox(width: 8),
                Text('Delete'),
              ],
            ),
          ),
        ],
      ),
      onTap: item.isCompleted ? () => _open(context, item) : null,
    );
  }

  void _open(BuildContext context, DownloadItem item) {
    final video = VideoItem(
      id: item.videoId,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
      uploader: item.uploader,
      url: item.videoUrl,
    );

    if (item.isMusic) {
      final path = item.audioPath ?? item.videoPath;
      if (path == null || !File(path).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The downloaded file is missing.')),
        );
        return;
      }
      final music = context.read<MusicPlaybackService>();
      final downloads = context.read<DownloadService>();
      final queue = [
        for (final m in downloads.getMusic())
          VideoItem(
            id: m.videoId,
            title: m.title,
            thumbnailUrl: m.thumbnailUrl,
            uploader: m.uploader,
            url: m.videoUrl,
          ),
      ];
      music.setQueue(queue, video);
      unawaited(music.play(video, localAudioPath: path));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MusicPlayerScreen(song: video)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(video: video, download: item),
        ),
      );
    }
  }

  String _subtitle(DownloadItem item) {
    final parts = <String>[
      if (item.type == DownloadType.videoAudio)
        'Video + audio'
      else if (item.type == DownloadType.videoOnly)
        'Video only'
      else
        'Audio',
      if (item.quality.isNotEmpty && item.quality != 'Best') item.quality,
      if (item.totalBytes > 0) _formatBytes(item.totalBytes),
    ];
    return parts.join(' • ');
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
