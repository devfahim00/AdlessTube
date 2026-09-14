import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'widgets.dart';
import 'region_service.dart';

/// ═══════════════════ হোমপেজ ═══════════════════
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

      // 1. Region trending
      final trending = await _service.getTrending(region: region);

      // 2. Subscribed channels এর video
      final subscribedUrls = storage.getSubscribedChannelUrls();
      final subFeed = <VideoItem>[];
      for (final url in subscribedUrls) {
        final vids = await _service.getChannelVideos(url);
        subFeed.addAll(vids.take(10));
      }

      // 3. Subscribed channel names দিয়ে related search
      final subNames = storage.getSubscribedChannelNames();
      final categoryFeed = <VideoItem>[];
      if (subNames.isNotEmpty) {
        final q = subNames.take(2).join(' ');
        final results = await _service.search(q);
        categoryFeed.addAll(results);
      }

      // Merge + dedupe
      final Set<String> seen = {};
      final merged = <VideoItem>[];
      for (final v in [...subFeed, ...categoryFeed, ...trending]) {
        if (!seen.contains(v.id)) {
          seen.add(v.id);
          merged.add(v);
        }
      }

      setState(() {
        _subscribedFeed = subFeed;
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
              child: Text(
                '$flag $region',
                style: const TextStyle(fontSize: 12),
              ),
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
          IconButton(
            icon: const Icon(Icons.library_music),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
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
                        title:
                            'Trending in ${RegionService.nameFor(region)}',
                        icon: Icons.trending_up,
                      ),
                      ..._feed.map(_buildTile),
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
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// ═══════════════════ অনুসন্ধান পেজ ═══════════════════
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _service = NewPipeService();
  List<VideoItem> _results = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _service.search(q);
      setState(() => _results = results);
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _search)
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) => VideoTile(
                    video: _results[i],
                    onTap: () async {
                      final storage = context.read<StorageService>();
                      await storage.addToHistory(_results[i]);
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PlayerScreen(video: _results[i]),
                          ),
                        );
                      }
                    },
                  ),
                ),
    );
  }
}

/// ═══════════════════ প্লেব্যাক পেজ ═══════════════════
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
      await _player.open(Media(_currentStream!.url));
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
      setState(() => _related = rel);
    } catch (_) {}
    setState(() => _loadingRelated = false);
  }

  Future<void> _changeQuality(VideoStreamInfo stream) async {
    final wasPlaying = _isPlaying;
    await _player.open(Media(stream.url));
    if (wasPlaying) await _player.play();
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
                final isCurrent = s.quality == _currentStream!.quality;
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
                      Text('${s.quality}  •  ${s.format}'),
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.video.uploader,
                                            style: TextStyle(
                                                color: Colors.grey[300],
                                                fontWeight: FontWeight.w500),
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

/// ═══════════════════ লাইব্রেরি পেজ ═══════════════════
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
      itemCount: subs.length,
      itemBuilder: (_, i) {
        final url = subs.keys.elementAt(i);
        final data = subs[url]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.red[900],
            child: Text(
              (data['name']?.toString() ?? '?')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(data['name']?.toString() ?? 'Unknown'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => storage.unsubscribe(url),
          ),
        );
      },
    );
  }
}
