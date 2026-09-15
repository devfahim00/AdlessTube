import 'dart:async';

import 'package:flutter/material.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;
import 'package:provider/provider.dart';

import '../models.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'player_screen.dart';
import 'shorts_screen.dart';

/// ═══════════════════════ CHANNEL BROWSE ═══════════════════════
class ChannelScreen extends StatefulWidget {
  final ChannelItem channel;
  const ChannelScreen({super.key, required this.channel});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen>
    with SingleTickerProviderStateMixin {
  final _service = NewPipeService();
  List<VideoItem> _videos = [];
  List<VideoItem> _shorts = [];
  PageToken? _videosNext;
  PageToken? _shortsNext;
  late final TabController _tab;
  bool _loading = true;
  bool _loadingMoreVideos = false;
  bool _loadingMoreShorts = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pages = await Future.wait([
        _service.getChannelTabPage(widget.channel.url, 'videos'),
        _service.getChannelTabPage(widget.channel.url, 'shorts'),
      ]);
      setState(() {
        _videos = pages[0].items;
        _videosNext = pages[0].next;
        _shorts = pages[1].items;
        _shortsNext = pages[1].next;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore(String tab) async {
    final isVideos = tab == 'videos';
    final next = isVideos ? _videosNext : _shortsNext;
    final loading = isVideos ? _loadingMoreVideos : _loadingMoreShorts;
    if (loading || next == null) return;
    setState(() {
      if (isVideos) {
        _loadingMoreVideos = true;
      } else {
        _loadingMoreShorts = true;
      }
    });
    try {
      final page = await _service.getChannelTabPage(
          widget.channel.url, tab, next: next);
      if (!mounted) return;
      setState(() {
        if (isVideos) {
          _videos.addAll(page.items);
          _videosNext = page.next;
        } else {
          _shorts.addAll(page.items);
          _shortsNext = page.next;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isVideos) {
            _loadingMoreVideos = false;
          } else {
            _loadingMoreShorts = false;
          }
        });
      }
    }
  }

  Widget _tabList(List<VideoItem> items, PageToken? next, String tab) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) unawaited(_loadMore(tab));
        return false;
      },
      child: ListView.builder(
        itemCount: items.length + (next == null ? 0 : 1),
        itemBuilder: (_, i) {
          if (i == items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return VideoTile(
            video: items[i],
            onTap: () async {
              final storage = context.read<StorageService>();
              final video = items[i];
              await storage.addToHistory(video);
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => tab == 'shorts'
                        ? ShortsScreen(shorts: items, initialIndex: i)
                        : PlayerScreen(video: video),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: widget.channel.thumbnailUrl.isNotEmpty
                      ? NetworkImage(widget.channel.thumbnailUrl)
                      : null,
                  child: widget.channel.thumbnailUrl.isEmpty
                      ? Text(
                          widget.channel.name.isNotEmpty
                              ? widget.channel.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 24),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.channel.subscriberCount != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${widget.channel.subscriberCount} subscribers',
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SubscribeButton(
            channelUrl: widget.channel.url,
            channelName: widget.channel.name,
            thumbnail: widget.channel.thumbnailUrl,
          ),
          const Divider(),
          TabBar(
            controller: _tab,
            tabs: const [Tab(text: 'Videos'), Tab(text: 'Shorts')],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : TabBarView(
                        controller: _tab,
                        children: [
                          _tabList(_videos, _videosNext, 'videos'),
                          _tabList(_shorts, _shortsNext, 'shorts'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
