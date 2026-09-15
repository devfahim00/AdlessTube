import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../music_playback_service.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import '../models.dart';

/// ═══════════════════════ SHORTS ═══════════════════════
class ShortsScreen extends StatefulWidget {
  final List<VideoItem>? shorts;
  final int initialIndex;

  const ShortsScreen({
    super.key,
    this.shorts,
    this.initialIndex = 0,
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
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      backgroundColor: Colors.black,
      body: _loading
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
                      itemCount: _shorts.length,
                      onPageChanged: (index) {
                        setState(() => _activeIndex = index);
                      },
                      itemBuilder: (_, index) => _ShortVideoPage(
                        key: ValueKey(_shorts[index].id),
                        video: _shorts[index],
                        active: index == _activeIndex,
                      ),
                    ),
    );
  }
}

class _ShortVideoPage extends StatefulWidget {
  final VideoItem video;
  final bool active;

  const _ShortVideoPage({
    super.key,
    required this.video,
    required this.active,
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
    if (widget.active) {
      unawaited(_start());
    }
  }

  @override
  void didUpdateWidget(covariant _ShortVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) {
      unawaited(_start());
    } else if (widget.active) {
      _player.play();
    } else {
      _player.pause();
    }
  }

  Future<void> _start() async {
    _started = true;
    final preference = context.read<StorageService>().defaultQuality;
    final music = context.read<MusicPlaybackService>();
    await music.stop();
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
      if (widget.active) {
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
