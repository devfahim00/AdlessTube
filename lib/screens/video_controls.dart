import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// YouTube-style video controls for the player.
///
/// * Single tap anywhere toggles play/pause; while paused a large pause
///   badge sits in the center of the video so the state is obvious.
/// * Double tap on the left/right half rewinds/forwards 10 seconds —
///   works inline (not only in fullscreen).
/// * Swiping down minimizes the video into the mini player (or exits
///   fullscreen when already fullscreen) — like the official app, there
///   is no back button on the video.
/// * Top bar: gear (settings) on the upper-right corner.
/// * Bottom bar: thin red progress bar, elapsed/total time and a
///   fullscreen toggle.
class YouTubeVideoControls extends StatefulWidget {
  final Player player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenSettings;

  /// Vertical swipe-down gesture on the video surface.
  final VoidCallback onSwipeDown;

  /// Whether UI animations are enabled (settings toggle).
  final bool animationsEnabled;

  const YouTubeVideoControls({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onOpenSettings,
    required this.onSwipeDown,
    this.animationsEnabled = true,
  });

  @override
  State<YouTubeVideoControls> createState() => _YouTubeVideoControlsState();
}

class _YouTubeVideoControlsState extends State<YouTubeVideoControls> {
  static const _hideAfter = Duration(seconds: 3);
  static const _swipeThreshold = 72.0;

  bool _visible = true;
  Timer? _hideTimer;
  Offset? _doubleTapPosition;
  int _seekFeedbackSide = 0; // -1 left | 0 none | 1 right
  Timer? _seekFeedbackTimer;
  double _dragValue = -1; // -1 = not dragging
  double _verticalDrag = 0; // accumulated downward drag, 0 = none

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  /// Single tap: toggle play/pause and flash the controls.
  void _onTap() {
    if (!mounted) return;
    setState(() => _visible = true);
    _scheduleHide();
    widget.player.playOrPause();
  }

  Future<void> _seekBy(int seconds) async {
    final position = widget.player.state.position;
    final duration = widget.player.state.duration;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await widget.player.seek(target);
  }

  void _showSeekFeedback(int side) {
    _seekFeedbackTimer?.cancel();
    setState(() => _seekFeedbackSide = side);
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedbackSide = 0);
    });
  }

  void _onDoubleTap() {
    final size = context.size;
    final position = _doubleTapPosition;
    var dx = 0.5;
    if (position != null && size != null && size.width > 0) {
      dx = position.dx / size.width;
    }
    if (dx < 0.5) {
      _seekBy(-10);
      _showSeekFeedback(-1);
    } else {
      _seekBy(10);
      _showSeekFeedback(1);
    }
  }

  Duration get _animDuration =>
      widget.animationsEnabled ? const Duration(milliseconds: 200) : Duration.zero;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final dragOffset = _verticalDrag * 0.25;
    return Transform.translate(
      offset: Offset(0, dragOffset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tap catcher — single tap play/pause, double tap seek, swipe
          // down minimizes into the mini player.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
            onDoubleTap: _onDoubleTap,
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 0) {
                setState(() => _verticalDrag += details.delta.dy);
              }
            },
            onVerticalDragEnd: (details) {
              final triggered = _verticalDrag >= _swipeThreshold;
              setState(() => _verticalDrag = 0);
              if (triggered) widget.onSwipeDown();
            },
            onVerticalDragCancel: () {
              if (mounted) setState(() => _verticalDrag = 0);
            },
            child: const SizedBox.expand(),
          ),
          // Swipe-down hint: the video drags with the finger and a small
          // chevron fades in past half the trigger distance.
          if (_verticalDrag > 8)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: (_verticalDrag / _swipeThreshold).clamp(0.0, 1.0),
                duration: Duration.zero,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Double-tap seek feedback (YouTube-style ripple).
          if (_seekFeedbackSide != 0)
            Align(
              alignment: _seekFeedbackSide < 0
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _seekFeedbackSide < 0
                            ? Icons.replay_10
                            : Icons.forward_10,
                        color: Colors.white,
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Paused badge: a large pause icon stays over the video while
          // playback is paused; nothing shows while playing.
          StreamBuilder<bool>(
            stream: player.stream.playing,
            builder: (context, playingSnapshot) {
              final playing = playingSnapshot.data ?? true;
              return StreamBuilder<bool>(
                stream: player.stream.buffering,
                builder: (context, bufferingSnapshot) {
                  final buffering = bufferingSnapshot.data ?? false;
                  if (playing || buffering) return const SizedBox.shrink();
                  return IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: _animDuration,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.pause,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Buffering spinner.
          StreamBuilder<bool>(
            stream: player.stream.buffering,
            builder: (context, snapshot) {
              final buffering = snapshot.data ?? false;
              if (!buffering) return const SizedBox.shrink();
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
          // Controls overlay.
          AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: _animDuration,
            child: IgnorePointer(
              ignoring: !_visible,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Top bar: gear only (back is a swipe down, like YT).
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white),
                            tooltip: 'Settings',
                            onPressed: () {
                              _scheduleHide();
                              widget.onOpenSettings();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Bottom bar: progress + time + fullscreen.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildBottomBar(player),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Player player) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
      child: SafeArea(
        top: false,
        child: StreamBuilder<Duration>(
          stream: player.stream.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = player.state.duration;
            final maxMs =
                duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
            final posMs = position.inMilliseconds.clamp(0, maxMs);
            final dragging = _dragValue >= 0;
            final value = dragging
                ? _dragValue
                : (posMs / maxMs).clamp(0.0, 1.0);
            final shownPosition = Duration(
              milliseconds: (value * maxMs).round(),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 34,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.red,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.red,
                      overlayColor: Colors.red.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: value.clamp(0.0, 1.0),
                      onChanged: duration.inMilliseconds > 0
                          ? (v) => setState(() => _dragValue = v)
                          : null,
                      onChangeEnd: duration.inMilliseconds > 0
                          ? (v) async {
                              await player.seek(
                                Duration(milliseconds: (v * maxMs).round()),
                              );
                              if (mounted) {
                                setState(() => _dragValue = -1);
                              }
                              _scheduleHide();
                            }
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 2),
                  child: Row(
                    children: [
                      Text(
                        '${_fmt(shownPosition)} / ${_fmt(duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          widget.isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                          size: 26,
                        ),
                        tooltip: widget.isFullscreen
                            ? 'Exit fullscreen'
                            : 'Fullscreen',
                        onPressed: () {
                          _scheduleHide();
                          widget.onToggleFullscreen();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }
}
