import 'dart:async';

import 'package:flutter/material.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;
import 'package:provider/provider.dart';

import '../models.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../suggestion_service.dart';
import '../widgets.dart';
import 'channel_screen.dart';
import 'player_screen.dart';

/// ═══════════════════════ SEARCH ═══════════════════════
///
/// Shows recent searches as history, live suggestions while typing and
/// loads more results endlessly as the user scrolls.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _service = NewPipeService();
  final _suggestions = SuggestionService();
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

  // Suggestions + history
  Timer? _debounce;
  List<String> _suggestionList = [];
  bool _showSuggestions = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tab.dispose();
    _controller.dispose();
    _suggestions.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    setState(() => _showSuggestions = true);
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestionList = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await _suggestions.getSuggestions(text);
      if (mounted) setState(() => _suggestionList = suggestions);
    });
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    // Remember every search so it shows up as history next time.
    unawaited(context.read<StorageService>().addSearchQuery(q));
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = q;
      _showSuggestions = false;
    });
    try {
      final vids = await _service.searchVideoPage(q);
      final chans = await _service.searchChannelPage(q);
      if (mounted) {
        setState(() {
          _videos = vids.items;
          _channels = chans.items;
          _videoNext = vids.next;
          _channelNext = chans.next;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchFromHistory(String query) {
    _controller.text = query;
    // Move the caret to the end so editing continues naturally.
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _search();
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
    if (_loadingMoreChannels || _channelNext == null || _lastQuery.isEmpty) {
      return;
    }
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
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
        bottom: _loading || _lastQuery.isEmpty || _showSuggestions
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
          ? const ListSkeleton()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _search)
              : _showSuggestions || _lastQuery.isEmpty
                  ? SearchHistoryAndSuggestions(
                      controller: _controller,
                      suggestions: _suggestionList,
                      onSearch: _search,
                      onSearchFromHistory: _searchFromHistory,
                      emptyHint: 'Search for videos or channels',
                    )
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
                                          child:
                                              CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    return VideoTile(
                                      video: _videos[i],
                                      onTap: () async {
                                        final storage =
                                            context.read<StorageService>();
                                        final navigator =
                                            Navigator.of(context);
                                        final video = _videos[i];
                                        await storage.addToHistory(video);
                                        navigator.push(
                                          pushPlayerRoute(
                                            PlayerScreen(video: video),
                                            animationsEnabled: storage
                                                .animationsEnabled,
                                          ),
                                        );
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
                                          child:
                                              CircularProgressIndicator(),
                                        ),
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
