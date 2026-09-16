import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../music_playback_service.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../video_playback_service.dart';
import '../widgets.dart';
import '../models.dart';

/// ═══════════════════════ SHORTS ═══════════════════════
class ShortsScreen extends StatefulWidget {
  final List<VideoItem>? shorts;
  final int initialIndex;

  /// Whether this screen is the visible tab right now — MainShell passes it
  /// so playback pauses while the user browses other tabs.
  final bool active;

  /// Where the top-left exit button lands (tab mode). Null when pushed as a
  /// full-screen route — then the button is a back arrow instead.
  final VoidCallback? onExit;

  const ShortsScreen({
    super.key,
    this.shorts,
    this.initialIndex = 0,
    this.active = true,
    this.onExit,
  });

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final _service = NewPipeService();
  List<VideoItem> _shorts = [];
  bool _loading = true;
  String? _error;
  int _activeIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    if (widget.shorts != null) {
      _shorts = widget.shorts!;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant ShortsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Coming (back) to the Shorts tab: nothing else may keep playing.
    if (widget.active && !oldWidget.active) {
      unawaited(_pauseBackgroundAudio());
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pauseBackgroundAudio() async {
    final music = context.read<MusicPlaybackService>();
    final vps = context.read<VideoPlaybackService>();
    try {
      await music.stop();
    } catch (_) {}
    try {
      await vps.pauseIfPlaying();
    } catch (_) {}
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
        watchHistory: storage.getHistory(),
      );
      if (mounted) setState(() => _shorts = shorts);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _exit() {
    final exit = widget.onExit;
    if (exit != null) {
      exit();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _shorts.isEmpty
                        ? const Center(
                            child: Text('No shorts found',
                                style: TextStyle(color: Colors.white)),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            scrollDirection: Axis.vertical,
                            // Builds the neighbour pages so the next short
                            // preloads (opens paused) — swipes start instantly.
                            allowImplicitScrolling: true,
                            itemCount: _shorts.length,
                            onPageChanged: (index) {
                              setState(() => _activeIndex = index);
                              // The swipe already preloads index + 1; keep
                              // streams warm two pages ahead too.
                              final ahead = index + 2;
                              if (ahead < _shorts.length) {
                                unawaited(
                                    _service.warmStreamCache(_shorts[ahead].url));
                              }
                            },
                            itemBuilder: (_, index) => _ShortVideoPage(
                              key: ValueKey(_shorts[index].id),
                              video: _shorts[index],
                              active: index == _activeIndex,
                              tabActive: widget.active,
                            ),
                          ),
          ),
          // Top-left exit — jumps to Home / Music / Library (tab mode) or
          // pops the route (shorts opened from a channel page).
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: widget.onExit == null ? 'Back' : 'Exit',
                onPressed: _exit,
                icon: Icon(
                  widget.onExit == null ? Icons.arrow_back : Icons.close,
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortVideoPage extends StatefulWidget {
  final VideoItem video;

  /// The page the pager is currently on.
  final bool active;

  /// Whether the Shorts tab itself is visible.
  final bool tabActive;

  const _ShortVideoPage({
    super.key,
    required this.video,
    required this.active,
    required this.tabActive,
  });

  @override
  State<_ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<_ShortVideoPage> {
  final _service = NewPipeService();
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  bool _failed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    // The active page starts playing; neighbour pages (built by
    // allowImplicitScrolling) preload with the player opened paused.
    unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant _ShortVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) {
      unawaited(_start());
    } else if (widget.active && widget.tabActive) {
      // Became the current page while the tab is visible — play, and make
      // sure no other audio is running.
      unawaited(_stopBackgroundAudio());
      unawaited(_player.play());
    } else {
      // Off-screen page or the whole Shorts tab is hidden.
      unawaited(_player.pause());
    }
  }

  Future<void> _stopBackgroundAudio() async {
    final music = context.read<MusicPlaybackService>();
    final vps = context.read<VideoPlaybackService>();
    try {
      await music.stop();
    } catch (_) {}
    try {
      await vps.pauseIfPlaying();
    } catch (_) {}
  }

  Future<void> _start() async {
    _started = true;
    final preference = context.read<StorageService>().defaultQuality;
    // Only the page the user is actually watching silences other audio.
    if (widget.active && widget.tabActive) {
      await _stopBackgroundAudio();
    }
    try {
      final streams = await _service.getAvailableStreams(widget.video.url);
      if (streams.isEmpty) {
        throw StateError('No playable stream');
      }
      final target = preference == 'Auto'
          ? 720
          : int.tryParse(preference.replaceAll('p', '')) ?? 720;
      final stream = streams.firstWhere(
        (candidate) {
          final match = RegExp(r'(\d{3,4})').firstMatch(candidate.quality);
          return match != null && int.parse(match.group(1)!) <= target;
        },
        orElse: () => streams.last,
      );
      await _player.open(Media(stream.url));
      if (stream.audioUrl != null) {
        await _player.setAudioTrack(AudioTrack.uri(stream.audioUrl!));
      }
      // Preloaded neighbours stay paused until they become active.
      if (widget.active && widget.tabActive) {
        await _player.play();
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
                  ? const Center(
                      child: Text('Unable to play this short',
                          style: TextStyle(color: Colors.white)),
                    )
                  : GestureDetector(
                      onTap: _player.playOrPause,
                      child: Video(
                        controller: _controller,
                        fit: BoxFit.contain,
                        controls: NoVideoControls,
                      ),
                    ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(widget.video.uploader,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
