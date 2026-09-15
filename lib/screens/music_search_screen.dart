import 'dart:async';

import 'package:flutter/material.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart'
    show PageToken;
import 'package:provider/provider.dart';

import '../models.dart';
import '../music_playback_service.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../suggestion_service.dart';
import '../widgets.dart';
import 'music_player_screen.dart';

/// ═══════════════════════ MUSIC SEARCH ═══════════════════════
///
/// Live suggestions while typing, endless results while scrolling.
class MusicSearchScreen extends StatefulWidget {
  const MusicSearchScreen({super.key});

  @override
  State<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends State<MusicSearchScreen> {
  final _controller = TextEditingController();
  final _service = NewPipeService();
  final _suggestions = SuggestionService();

  List<VideoItem> _results = [];
  PageToken? _next;
  bool _loading = false;
  bool _loadingMore = false;
  String _lastQuery = '';
  String? _error;

  Timer? _debounce;
  List<String> _suggestionList = [];
  bool _showSuggestions = true;

  @override
  void dispose() {
    _debounce?.cancel();
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
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    // Remember every search so it shows up as history next time.
    unawaited(context.read<StorageService>().addSearchQuery(query));
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = query;
      _showSuggestions = false;
    });
    try {
      final page = await _service.searchVideoPage('$query music');
      if (mounted) {
        setState(() {
          _results =
              page.items.where((song) => !song.isShort && !song.isLive).toList();
          _next = page.next;
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
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _search();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _next == null || _lastQuery.isEmpty) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page =
          await _service.searchVideoPage('$_lastQuery music', next: _next);
      if (mounted) {
        setState(() {
          _results.addAll(
            page.items.where((song) => !song.isShort && !song.isLive),
          );
          _next = page.next;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openSong(VideoItem song) async {
    final storage = context.read<StorageService>();
    await storage.addToHistory(song);
    if (!mounted) return;
    context.read<MusicPlaybackService>().setQueue(_results, song);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => MusicPlayerScreen(song: song)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: 'Search songs, artists or albums',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _search,
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
        ],
      ),
      body: _loading
          ? const MusicListSkeleton()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _search)
              : _showSuggestions || _lastQuery.isEmpty
                  ? SearchHistoryAndSuggestions(
                      controller: _controller,
                      suggestions: _suggestionList,
                      onSearch: _search,
                      onSearchFromHistory: _searchFromHistory,
                      emptyHint: 'Search for music to get started',
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 300) {
                          unawaited(_loadMore());
                        }
                        return false;
                      },
                      child: _results.isEmpty
                          ? const Center(child: Text('No songs found'))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount:
                                  _results.length + (_next == null ? 0 : 1),
                              itemBuilder: (_, index) {
                                if (index == _results.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final song = _results[index];
                                final liked = storage.isSongLiked(song.id);
                                return MusicListTile(
                                  song: song,
                                  liked: liked,
                                  onTap: () => _openSong(song),
                                  onToggleLike: () =>
                                      storage.toggleLikedSong(song),
                                );
                              },
                            ),
                    ),
    );
  }
}
