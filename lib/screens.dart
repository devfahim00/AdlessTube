import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'widgets.dart';
import 'region_service.dart';

/// ═══════════════════════ MAIN SHELL ═══════════════════════
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
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
  bool _loading = false;
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
      final vids = await _service.searchVideos(q);
      final chans = await _service.searchChannels(q);
      setState(() {
        _videos = vids;
        _channels = chans;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
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
                            : ListView.builder(
                                itemCount: _videos.length,
                                itemBuilder: (_, i) => VideoTile(
                                  video: _videos[i],
                                  onTap: () async {
                                    final storage =
                                        context.read<StorageService>();
                                    await storage.addToHistory(_videos[i]);
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PlayerScreen(
                                              video: _videos[i]),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                        _channels.isEmpty
                            ? const Center(child: Text('No channels'))
                            : ListView.builder(
                                itemCount: _channels.length,
                                itemBuilder: (_, i) => ChannelTile(
                                  channel: _channels[i],
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChannelScreen(
                                          channel: _channels[i]),
                                    ),
                                  ),
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

class _ChannelScreenState extends State<ChannelScreen> {
  final _service = NewPipeService();
  List<VideoItem> _videos = [];
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
      final vids = await _service.getChannelVideos(widget.channel.url);
      setState(() => _videos = vids);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _videos.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.video_library_outlined,
                                    size: 60, color: Colors.grey),
                                const SizedBox(height: 12),
                                const Text('No videos found'),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _videos.length,
                            itemBuilder: (_, i) => VideoTile(
                              video: _videos[i],
                              onTap: () async {
                                final storage =
                                    context.read<StorageService>();
                                await storage.addToHistory(_videos[i]);
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PlayerScreen(video: _videos[i]),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════════ PLAYER (HD via audio merge) ═══════════════════════
class PlayerScreen extends StatefulWidget {
  final VideoItem video;
  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _service = NewPipeService();

  bool _loading = true;
  String? _error;
  bool _isPlaying = false;

  List<VideoStreamInfo> _streams = [];
  VideoStreamInfo? _currentStream;
  List<VideoItem> _related = [];
  bool _loadingRelated = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

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
      _streams = streams;
      _currentStream = streams.first;
      await _openStream(_currentStream!);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// video-only হলে audio merge করে open করি
  Future<void> _openStream(VideoStreamInfo stream) async {
    if (stream.needsAudioMerge) {
      // Video + Audio merge
      await _player.open(
        Media(stream.url, extras: {'audio': stream.audioUrl}),
      );
    } else {
      await _player.open(Media(stream.url));
    }
    await _player.play();
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
    await _openStream(stream);
    if (!wasPlaying) await _player.pause();
    setState(() => _currentStream = stream);
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
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
                      Text(s.quality),
                      const SizedBox(width: 8),
                      if (s.format == 'video-only')
                        const Icon(Icons.hd, size: 14, color: Colors.red),
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_currentStream!.format ==
                                      'video-only')
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Icon(Icons.hd,
                                          size: 14, color: Colors.red),
                                    ),
                                  Text(
                                    _currentStream!.quality,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ],
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
