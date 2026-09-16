import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'channel_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

/// ═══════════════════════ LIBRARY ═══════════════════════
///
/// History, Subscriptions, Saved and Downloads — all local data in one
/// place, each in its own tab.
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
    _tab = TabController(length: 4, vsync: this);
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'History', icon: Icon(Icons.history)),
            Tab(text: 'Subscriptions', icon: Icon(Icons.subscriptions)),
            Tab(text: 'Saved', icon: Icon(Icons.bookmark)),
            Tab(text: 'Downloads', icon: Icon(Icons.download)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _HistoryTab(),
          _SubscriptionsTab(),
          _SavedTab(),
          DownloadsList(bottomPadding: 96),
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
                pushPlayerRoute(
                  PlayerScreen(video: history[i]),
                  animationsEnabled: context
                      .read<StorageService>()
                      .animationsEnabled,
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

class _SavedTab extends StatelessWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final saved = storage.getSavedVideos();

    if (saved.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No saved videos yet.\nTap Save on any video to find it here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: saved.length,
      itemBuilder: (_, i) => Row(
        children: [
          Expanded(
            child: VideoTile(
              video: saved[i],
              onTap: () => Navigator.push(
                context,
                pushPlayerRoute(
                  PlayerScreen(video: saved[i]),
                  animationsEnabled: context
                      .read<StorageService>()
                      .animationsEnabled,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_remove_outlined),
            tooltip: 'Remove from saved',
            onPressed: () => storage.toggleSavedVideo(saved[i]),
          ),
        ],
      ),
    );
  }
}
