import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'widgets.dart';
import 'region_service.dart';

/// ═══════════════════ হোমপেজ — Region + Subscription feed ═══════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = NewPipeService();
  List<VideoItem> _feed = [];
  List<VideoItem> _trending = [];
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

      // 1. Region trending (live filtered)
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
        _trending = trending;
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
                '${RegionService.flagFor(region)} ${region}',
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
                        title: 'Trending in ${RegionService.nameFor(region)}',
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
          : _error !=
