import 'dart:async';
import 'dart:io';

import 'package:android_pip/android_pip.dart';
import 'package:android_pip/pip_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'widgets.dart';
import 'region_service.dart';

/// ═══════════════════════ MAIN SHELL (Bottom Pill Navbar) ═══════════════════════
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    ShortsScreen(),
    LibraryScreen(),
    MenuScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _PillNavBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _PillNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _PillNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.play_circle_outline, Icons.play_circle_fill, 'Shorts'),
      (Icons.video_library_outlined, Icons.video_library, 'Library'),
      (Icons.menu, Icons.menu, 'Menu'),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(items.length, (i) {
            final selected = i == currentIndex;
            final (outlined, filled, label) = items[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? filled : outlined,
                        color: selected ? Colors.red : Colors.grey[400],
                        size: 22,
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// ═══════════════════════ HOME ═══════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = NewPipeService();
  List<VideoItem> _feed = [];
  List<VideoItem> _subscribedFeed = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final storage = context.read<StorageService>();
      final region = storage.regionCode;

      final trending = await _service.getTrending(region: region);

      final subscribedUrls = storage.getSubscribedChannelUrls();
      final subFeed = <VideoItem>[];
      for (final url in subscribedUrls) {
        final vids = await _service.getChannelVideos(url);
        subFeed.addAll(vids.take(10));
      }

      final Set<String> seen = {};
      final merged = <VideoItem>[];
      for (final v in [...subFeed, ...trending]) {
        if (!seen.contains(v.id) && !v.isLive) {
          seen.add(v.id);
          merged.add(v);
        }
      }

      setState(() {
        _subscribedFeed = subFeed.where((v) => !v.isLive).toList();
        _feed = merged;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final region = storage.regionCode;
    final flag = RegionService.flagFor(region);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AdlessTube'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$flag $region',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      if (_subscribedFeed.isNotEmpty) ...[
                        const _SectionHeader(
                          title: 'From your subscriptions',
                          icon: Icons.subscriptions,
                        ),
                        ..._subscribedFeed.map(_buildTile),
                        const Divider(),
                      ],
                      _SectionHeader(
                        title: 'Trending in ${RegionService.nameFor(region)}',
                        icon: Icons.trending_up,
                      ),
                      ..._feed.map(_buildTile),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTile(VideoItem video) {
    return VideoTile(
      video: video,
      onTap: () async {
        final storage = context.read<StorageService>();
        await storage.addToHistory(video);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
          );
        }
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.red),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// ═══════════════════════ SEARCH ═══════════════════════
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _service = NewPipeService();
  late TabController _tab;

  List<VideoItem> _videos = [];
  List<ChannelItem> _channels = [];
  PageToken? _videoNext;
  PageToken? _channelNext;
  bool _loading = false;
  bool _loadingMoreVideos = false;
  bool _loadingMoreChannels = false;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = q;
    });
    try {
      final vids = await _service.searchVideoPage(q);
      final chans = await _service.searchChannelPage(q);
      setState(() {
        _videos = vids.items;
        _channels = chans.items;
        _videoNext = vids.next;
        _channelNext = chans.next;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_loadingMoreVideos || _videoNext == null || _lastQuery.isEmpty) return;
    setState(() => _loadingMoreVideos = true);
    try {
      final page = await _service.searchVideoPage(_lastQuery, next: _videoNext);
      if (mounted) {
        setState(() {
          _videos.addAll(page.items);
          _videoNext = page.next;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMoreVideos = false);
    }
  }

  Future<void> _loadMoreChannels() async {
    if (_loadingMoreChannels || _channelNext == null || _lastQuery.isEmpty) return;
    setState(() => _loadingMoreChannels = true);
    try {
      final page = await _service.searchChannelPage(
        _lastQuery,
        next: _channelNext,
      );
      if (mounted) {
        setState(() {
          _channels.addAll(page.items);
          _channelNext = page.next;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMoreChannels = false);
    }
  }

  bool _loadOnScroll(
    ScrollNotification notification,
    Future<void> Function() load,
  ) {
    if (notification.metrics.extentAfter < 300) unawaited(load());
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search YouTube...',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
        bottom: _loading || _lastQuery.isEmpty
            ? null
            : TabBar(
                controller: _tab,
                tabs: [
                  Tab(text: 'Videos (${_videos.length})'),
                  Tab(text: 'Channels (${_channels.length})'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _search)
              : _lastQuery.isEmpty
                  ? const Center(
                      child: Text('Search for videos or channels'))
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _videos.isEmpty
                            ? const Center(child: Text('No videos'))
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) =>
                                    _loadOnScroll(n, _loadMoreVideos),
                                child: ListView.builder(
                                  itemCount: _videos.length +
                                      (_videoNext == null ? 0 : 1),
                                  itemBuilder: (_, i) {
                                    if (i == _videos.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    }
                                    return VideoTile(
                                      video: _videos[i],
                                      onTap: () async {
                                        final storage = context.read<StorageService>();
                                        final video = _videos[i];
                                        await storage.addToHistory(video);
                                        if (mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PlayerScreen(
                                                  video: video),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                        _channels.isEmpty
                            ? const Center(child: Text('No channels'))
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) =>
                                    _loadOnScroll(n, _loadMoreChannels),
                                child: ListView.builder(
                                  itemCount: _channels.length +
                                      (_channelNext == null ? 0 : 1),
                                  itemBuilder: (_, i) {
                                    if (i == _channels.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    }
                                    return ChannelTile(
                                      channel: _channels[i],
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChannelScreen(
                                              channel: _channels[i]),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ],
                    ),
    );
  }
}

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
                  MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
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

/// ═══════════════════════ PLAYER ═══════════════════════
class PlayerScreen extends StatefulWidget {
  final VideoItem video;
  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  late final StorageService _storage;
  final _service = NewPipeService();

  bool _loading = true;
  String? _error;
  bool _isPlaying = false;

  List<VideoStreamInfo> _streams = [];
  VideoStreamInfo? _currentStream;
  List<VideoItem> _related = [];
  bool _loadingRelated = false;
  Duration _lastSavedPosition = Duration.zero;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.position.listen((position) {
      if ((position - _lastSavedPosition).inSeconds >= 5) {
        _savePlaybackState(position);
      }
    });

    if (Platform.isAndroid) unawaited(_enableAutoPip());

    _loadStreams();
    _loadRelated();
  }

  Future<void> _loadStreams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final streams = await _service.getAvailableStreams(widget.video.url);
      if (streams.isEmpty) {
        setState(() {
          _error = 'No playable stream found.';
          _loading = false;
        });
        return;
      }
      final saved = _storage.getPlaybackState(widget.video.id);
      final savedQuality = saved?['quality'];
      final savedFormat = saved?['format'];
      final savedPosition = Duration(
        milliseconds: (saved?['positionMs'] as int?) ?? 0,
      );
      _streams = streams;
      _currentStream = streams.first;
      for (final stream in streams) {
        if (stream.quality == savedQuality && stream.format == savedFormat) {
          _currentStream = stream;
          break;
        }
      }
      await _openStream(_currentStream!, start: savedPosition);
      await _player.play();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadRelated() async {
    setState(() => _loadingRelated = true);
    try {
      final rel = await _service.getRelatedVideos(widget.video.url);
      setState(() => _related = rel.where((v) => !v.isLive).toList());
    } catch (_) {}
    setState(() => _loadingRelated = false);
  }

  Future<void> _changeQuality(VideoStreamInfo stream) async {
    final wasPlaying = _isPlaying;
    final position = _player.state.position;
    await _openStream(stream, start: position);
    if (wasPlaying) {
      await _player.play();
    } else {
      await _player.pause();
    }
    setState(() => _currentStream = stream);
    _savePlaybackState(position);
  }

  Future<void> _changeSpeed(double speed) async {
    await _player.setRate(speed);
    if (mounted) setState(() => _playbackSpeed = speed);
  }

  Future<void> _enableAutoPip() async {
    try {
      await AndroidPIP().setAutoPipMode();
    } catch (_) {
      // Auto-PiP requires Android 12; the PiP button remains available.
    }
  }

  Future<void> _openStream(VideoStreamInfo stream, {Duration? start}) async {
    await _player.open(Media(stream.url, start: start));
    if (stream.audioUrl != null) {
      await _player.setAudioTrack(AudioTrack.uri(stream.audioUrl!));
    }
  }

  void _savePlaybackState([Duration? position]) {
    final stream = _currentStream;
    if (stream == null) return;
    final currentPosition = position ?? _player.state.position;
    _lastSavedPosition = currentPosition;
    unawaited(_storage.savePlaybackState(
          videoId: widget.video.id,
          position: currentPosition,
          quality: stream.quality,
          format: stream.format,
        ));
  }

  void _openRelated(VideoItem v) async {
    final storage = context.read<StorageService>();
    await storage.addToHistory(v);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(video: v)),
    );
  }

  @override
  void dispose() {
    _savePlaybackState();
    unawaited(_player.stop());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _stopBeforeLeaving() async {
    _savePlaybackState();
    await _player.stop();
  }

  @override
  Widget build(BuildContext context) {
    final playerOnly = ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(controller: _controller),
        ),
      ),
    );
    final page = Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt),
              tooltip: 'Picture in Picture',
              onPressed: () async {
                try {
                  await AndroidPIP().enterPipMode();
                } catch (_) {}
              },
            ),
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            tooltip: 'Playback speed',
            onSelected: _changeSpeed,
            itemBuilder: (_) => [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0]
                .map((speed) => PopupMenuItem(
                      value: speed,
                      child: Text(
                        '${_playbackSpeed == speed ? '✓  ' : '    '}${speed}x',
                      ),
                    ))
                .toList(),
          ),
          if (_currentStream != null)
            PopupMenuButton<VideoStreamInfo>(
              icon: const Icon(Icons.high_quality),
              tooltip: 'Quality',
              onSelected: _changeQuality,
              itemBuilder: (_) => _streams.map((s) {
                final isCurrent = s.quality == _currentStream!.quality &&
                    s.format == _currentStream!.format;
                return PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        isCurrent
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: isCurrent ? Colors.red : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${s.quality}${s.format == 'muxed' ? '' : ' (${s.format})'}',
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _loadStreams,
                            child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: _controller,
                        controls: AdaptiveVideoControls,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      color: Colors.black,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(_isPlaying
                                ? Icons.pause
                                : Icons.play_arrow),
                            color: Colors.white,
                            onPressed: () => _player.playOrPause(),
                          ),
                          if (_currentStream != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _currentStream!.quality,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.video.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {
                                          if (widget
                                              .video.uploaderUrl.isNotEmpty) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ChannelScreen(
                                                  channel: ChannelItem(
                                                    url: widget
                                                        .video.uploaderUrl,
                                                    name: widget
                                                        .video.uploader,
                                                    thumbnailUrl: widget
                                                        .video.thumbnailUrl,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.video.uploader,
                                              style: TextStyle(
                                                  color: Colors.grey[300],
                                                  fontWeight:
                                                      FontWeight.w500),
                                            ),
                                            if (widget.video.viewCount !=
                                                null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${widget.video.viewCount} views',
                                                style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    SubscribeButton(
                                      channelUrl: widget.video.uploaderUrl,
                                      channelName: widget.video.uploader,
                                      thumbnail: widget.video.thumbnailUrl,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.grey),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Text(
                              'Related videos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_loadingRelated)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator()),
                            )
                          else if (_related.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'No related videos',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          else
                            ..._related.map(
                              (v) => VideoTile(
                                video: v,
                                onTap: () => _openRelated(v),
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
    );
    final pipPage = Platform.isAndroid
        ? PipWidget(pipChild: playerOnly, child: page)
        : page;
    return WillPopScope(
      onWillPop: () async {
        await _stopBeforeLeaving();
        return true;
      },
      child: pipPage,
    );
  }
}

/// ═══════════════════════ LIBRARY ═══════════════════════
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'History', icon: Icon(Icons.history)),
            Tab(text: 'Subscriptions', icon: Icon(Icons.subscriptions)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _HistoryTab(),
          _SubscriptionsTab(),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final history = storage.getHistory();

    if (history.isEmpty) {
      return const Center(child: Text('No history yet'));
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: storage.clearHistory,
            tooltip: 'Clear history',
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (_, i) => VideoTile(
              video: history[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(video: history[i]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SubscriptionsTab extends StatelessWidget {
  const _SubscriptionsTab();

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final subs = storage.getSubscriptions();

    if (subs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No subscriptions yet.\nSubscribe from any video to see channels here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: subs.length,
      itemBuilder: (_, i) {
        final url = subs.keys.elementAt(i);
        final data = subs[url]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.red[900],
            backgroundImage:
                (data['thumbnail']?.toString() ?? '').isNotEmpty
                    ? NetworkImage(data['thumbnail'].toString())
                    : null,
            child: (data['thumbnail']?.toString() ?? '').isEmpty
                ? Text(
                    (data['name']?.toString() ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  )
                : null,
          ),
          title: Text(data['name']?.toString() ?? 'Unknown'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChannelScreen(
                channel: ChannelItem(
                  url: url,
                  name: data['name']?.toString() ?? '',
                  thumbnailUrl: data['thumbnail']?.toString() ?? '',
                ),
              ),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => storage.unsubscribe(url),
          ),
        );
      },
    );
  }
}

/// ═══════════════════════ MENU (শুধু Region) ═══════════════════════
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final region = storage.regionCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          ListTile(
            leading: const Icon(Icons.public, color: Colors.red),
            title: const Text('Region'),
            subtitle: Text(
              '${RegionService.flagFor(region)} ${RegionService.nameFor(region)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegionChangeScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.telegram, color: Color(0xFF229ED9)),
            title: const Text('Join Telegram'),
            subtitle: const Text('t.me/projectredfox'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              await launchUrl(
                Uri.parse('https://t.me/projectredfox'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'AdlessTube v1.0.0\nAd-free YouTube client',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final _service = NewPipeService();
  List<VideoItem> _shorts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storage = context.read<StorageService>();
      final shorts = await _service.getShorts(
        region: storage.regionCode,
        subscribedChannels: storage.getSubscribedChannelUrls(),
      );
      if (mounted) setState(() => _shorts = shorts);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shorts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _shorts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 220),
                          Center(child: Text('No shorts found')),
                        ])
                      : ListView.builder(
                          itemCount: _shorts.length,
                          itemBuilder: (_, i) => VideoTile(
                            video: _shorts[i],
                            onTap: () async {
                              final storage = context.read<StorageService>();
                              final video = _shorts[i];
                              await storage.addToHistory(video);
                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlayerScreen(video: video),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: storage.themeMode,
            title: const Text('Auto'),
            subtitle: const Text('Use device setting'),
            onChanged: (mode) => storage.setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: storage.themeMode,
            title: const Text('Light'),
            onChanged: (mode) => storage.setThemeMode(mode!),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: storage.themeMode,
            title: const Text('Dark'),
            onChanged: (mode) => storage.setThemeMode(mode!),
          ),
        ],
      ),
    );
  }
}

class RegionChangeScreen extends StatelessWidget {
  const RegionChangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Region')),
      body: ListView.builder(
        itemCount: RegionService.regions.length,
        itemBuilder: (_, i) {
          final r = RegionService.regions[i];
          final storage = context.read<StorageService>();
          final isSelected = storage.regionCode == r['code'];
          return ListTile(
            leading:
                Text(r['flag']!, style: const TextStyle(fontSize: 28)),
            title: Text(r['name']!),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            selected: isSelected,
            onTap: () async {
              await context.read<StorageService>().setRegion(r['code']!);
              if (context.mounted) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
