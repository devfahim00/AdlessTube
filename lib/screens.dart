import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'newpipe_service.dart';
import 'storage_service.dart';
import 'widgets.dart';

/// হোমপেজ — ট্রেন্ডিং
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = NewPipeService();
  List<VideoItem> _trending = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _service.getTrending();
      setState(() => _trending = list);
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
        title: const Text('AdlessTube'),
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
              : ListView.builder(
                  itemCount: _trending.length,
                  itemBuilder: (_, i) => VideoTile(
                    video: _trending[i],
                    onTap: () async {
                      final storage = context.read<StorageService>();
                      await storage.addToHistory(_trending[i]);
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(video: _trending[i]),
                          ),
                        );
                      }
                    },
                  ),
                ),
    );
  }
}

/// অনুসন্ধান পেজ
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
    setState(() { _loading = true; _error = null; });
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
                            builder: (_) => PlayerScreen(video: _results[i]),
                          ),
                        );
                      }
                    },
                  ),
                ),
    );
  }
}

/// প্লেব্যাক পেজ — media_kit দিয়ে সত্যিকারের প্লেব্যাক
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

  @override
  void initState() {
    super.initState();
    // Player এবং VideoController তৈরি করুন
    _player = Player();
    _controller = VideoController(_player);

    // play/pause অবস্থা শুনুন
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    // স্ট্রিম লোড করুন
    _loadStream();
  }

  Future<void> _loadStream() async {
    setState(() { _loading = true; _error = null; });
    try {
      final streamUrl = await _service.getBestMuxedStreamUrl(widget.video.url);
      if (streamUrl == null) {
        setState(() {
          _error = 'No playable stream found (video may be too high resolution or live)';
          _loading = false;
        });
        return;
      }
      // media_kit দিয়ে খুলুন এবং চালান
      await _player.open(Media(streamUrl));
      await _player.play();
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
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
        title: Text(widget.video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        const Icon(Icons.error_outline, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadStream, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ভিডিও এলাকা
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: _controller,
                        controls: AdaptiveVideoControls,
                      ),
                    ),
                    // নিয়ন্ত্রণ বার
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.black,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            color: Colors.white,
                            onPressed: () => _player.playOrPause(),
                          ),
                        ],
                      ),
                    ),
                    // ভিডিও তথ্য
                    Expanded(
                      child: SingleChildScrollView(
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
                            const SizedBox(height: 8),
                            Text(
                              widget.video.uploader,
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// লাইব্রেরি পেজ — ইতিহাস
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final history = storage.getHistory();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: storage.clearHistory,
            ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text('No history yet'))
          : ListView.builder(
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
    );
  }
}
