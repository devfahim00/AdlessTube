import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// YouTube-style video controls for the player.
///
/// * Single tap anywhere toggles play/pause.
/// * Double tap on the left/right half rewinds/forwards 10 seconds —
///   works inline (not only in fullscreen).
/// * Top bar: back button + gear (settings) on the upper-right corner.
/// * Bottom bar: thin red progress bar, elapsed/total time and a
///   fullscreen toggle.
class YouTubeVideoControls extends StatefulWidget {
  final Player player;
  final bool isFullscreen;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenSettings;

  const YouTubeVideoControls({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.onOpenSettings,
  });

  @override
  State<YouTubeVideoControls> createState() => _YouTubeVideoControlsState();
}

class _YouTubeVideoControlsState extends State<YouTubeVideoControls> {
  static const _hideAfter = Duration(seconds: 3);

  bool _visible = true;
  Timer? _hideTimer;
  Offset? _doubleTapPosition;
  int _seekFeedbackSide = 0; // -1 left | 0 none | 1 right
  Timer? _seekFeedbackTimer;
  double _dragValue = -1; // -1 = not dragging

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

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Tap catcher — single tap play/pause, double tap seek.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
          onDoubleTap: _onDoubleTap,
          child: const SizedBox.expand(),
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
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_visible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Top bar: back + gear.
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
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          tooltip: 'Back',
                          onPressed: widget.onBack,
                        ),
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
