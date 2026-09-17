import 'dart:async';
import 'dart:io';

import 'package:android_pip/android_pip.dart';
import 'package:android_pip/pip_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../download_service.dart';
import '../models.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../video_playback_service.dart';
import '../widgets.dart';
import 'channel_screen.dart';
import 'video_audio_screen.dart';
import 'video_controls.dart';

/// ═══════════════════════ PLAYER ═══════════════════════
///
/// YouTube-style player built on top of [VideoPlaybackService]:
/// * video area with custom controls (tap to pause, double-tap to seek,
///   gear menu with quality + playback speed, fullscreen),
/// * action row under the title with Save / Share / Download / PiP,
/// * related videos below,
/// * pressing back minimizes the video into the floating mini player —
///   it keeps playing above the navbar and reopens from there.
class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  /// When set, playback uses the local downloaded files instead of network.
  final DownloadItem? download;

  const PlayerScreen({super.key, required this.video, this.download});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlaybackService _vps;
  final _service = NewPipeService();

  bool _isFullscreen = false;
  List<VideoItem> _related = [];
  bool _loadingRelated = false;
  bool _switchingToAudio = false;

  /// This page is being REPLACED by the next one (related video, Now
  /// Playing, downloaded copy) — the replacement pop must not shrink
  /// the video into the mini player, only a genuine back gesture does.
  bool _replacing = false;

  // ── Channel info (subscriber count under the channel name) ──
  int? _subscriberCount;
  bool _loadingChannelInfo = false;

  @override
  void initState() {
    super.initState();
    _vps = context.read<VideoPlaybackService>();

    // Attach to an already playing video (opened back from the mini player
    // or switching to a related video); otherwise start a fresh one.
    final alreadyLoaded =
        _vps.currentVideo?.id == widget.video.id && _vps.currentVideo != null;
    if (alreadyLoaded && !_vps.needsReload) {
      _vps.resumePage();
      // Opening the video itself always means video: an audio-only
      // session for it (feed tap while listening in the background)
      // restores the video track — playback continues at the exact
      // spot the audio reached.
      if (_vps.audioOnlyMode) {
        unawaited(_vps.exitAudioOnly());
      }
    } else {
      // Also covers a RESTORED audio session (previous app run) for
      // this same video: it has no media loaded yet, so the feed tap
      // plays it properly — video mode, at the saved spot.
      unawaited(_vps.open(widget.video, download: widget.download));
    }
    _loadRelated();
    unawaited(_loadChannelInfo());
  }

  /// Fetches the channel's subscriber count for the channel row (the
  /// video's own view count shows under the title instead, exactly
  /// like the official app).
  Future<void> _loadChannelInfo() async {
    final url = widget.video.uploaderUrl;
    if (url.isEmpty) return;
    setState(() => _loadingChannelInfo = true);
    try {
      final profile = await _service.getChannelProfile(url);
      if (mounted && profile.subscriberCount != null) {
        setState(() => _subscriberCount = profile.subscriberCount);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingChannelInfo = false);
  }

  Future<void> _loadRelated({bool force = false}) async {
    setState(() => _loadingRelated = true);
    try {
      final rel = await _service.getRelatedVideos(
        widget.video.url,
        forceRefresh: force,
      );
      if (mounted) {
        setState(() => _related = rel.where((v) => !v.isLive).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRelated = false);
  }

  Future<void> _openRelated(VideoItem v) async {
    final storage = context.read<StorageService>();
    // The navigator is captured before the await: if this page gets
    // replaced while history is being written (e.g. a pending
    // audio-only toggle lands), the tapped video still opens on top
    // of whatever is showing now.
    final navigator = Navigator.of(context);
    final animations = storage.animationsEnabled;
    await storage.addToHistory(v);
    _replacing = true; // our replacement pop is not a minimize
    navigator.pushReplacement(
      pushPlayerRoute(
        PlayerScreen(video: v),
        animationsEnabled: animations,
      ),
    );
  }

  /// Audio-only mode: the same player keeps running with its video
  /// track disabled — the audio continues from this exact spot and the
  /// dedicated Now Playing screen takes over (notification controls
  /// included). The music session is never touched.
  Future<void> _startAudioOnly() async {
    if (_switchingToAudio) return;
    // Instant feedback: the pill lights up and swaps to a spinner while
    // the toggle runs.
    setState(() => _switchingToAudio = true);
    try {
      final started = await _vps.enterAudioOnly();
      if (!mounted) return;
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Audio mode is unavailable — the video keeps playing'),
          ),
        );
        return;
      }
      // The toggle raced with opening another video (its page is
      // already up) — don't layer Now Playing on top of it.
      if (_vps.currentVideo?.id != widget.video.id) return;
      _replacing = true; // our replacement pop is not a minimize
      Navigator.pushReplacement(
        context,
        pushPlayerRoute(
          const VideoAudioScreen(),
          animationsEnabled:
              context.read<StorageService>().animationsEnabled,
        ),
      );
    } finally {
      if (mounted) setState(() => _switchingToAudio = false);
    }
  }

  // ─────────── Fullscreen ───────────

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() => _isFullscreen = true);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _isFullscreen = false);
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

  /// Cycles how the video fills the player surface: Fit → Crop → Stretch.
  /// Persisted in settings so every player remembers the choice.
  void _cycleVideoFit() {
    final storage = context.read<StorageService>();
    const order = StorageService.videoFitModes;
    final next =
        order[(order.indexOf(storage.videoFitMode) + 1) % order.length];
    storage.setVideoFitMode(next);
  }

  /// Swipe down on the video: in fullscreen it exits fullscreen, inline
  /// it shrinks the video into the mini player — exactly like the
  /// official YouTube app (there is no back button anymore).
  void _onSwipeDown() {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      _minimizeAndLeave();
    }
  }

  /// Back from the player shrinks the video into the floating mini player
  /// instead of stopping it — exactly like the official YouTube app.
  void _minimizeAndLeave() {
    _vps.minimize();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // The service keeps the video playing in the mini player; this page
    // only restores the system UI.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─────────── Settings (gear) sheet ───────────

  static const _speeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// Dedicated dubbing-language sheet — reachable straight from the
  /// audio pill under the video, no gear menu needed.
  Future<void> _openAudioSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                'Audio language',
                style: TextStyle(
                  color: isDark ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final track in _vps.audioTracks)
                    _audioTrackRow(track, isDark, sheetContext),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettingsSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // The sheet listens to the playback service so speed/quality taps
      // show their selected state immediately — no reopen needed.
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: _vps,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Text(
                  'Playback speed',
                  style: TextStyle(
                    color: isDark ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final speed in _speeds)
                      _speedChip(speed, isDark),
                  ],
                ),
              ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  'Quality',
                  style: TextStyle(
                    color: isDark ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (widget.download != null)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.download_done,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'Playing downloaded file (${widget.download!.quality})',
                    style: TextStyle(color: isDark ? Colors.white : null),
                  ),
                )
              else if (_vps.streams.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No other qualities available right now.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final stream in _vps.streams)
                        _qualityRow(stream, isDark, sheetContext),
                    ],
                  ),
                ),
              // Dubbed audio languages live in their own dedicated sheet
              // reachable from the audio pill in the action row.
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _audioTrackRow(
      AudioTrackOption track, bool isDark, BuildContext sheetContext) {
    final isCurrent = _vps.currentAudioTrack?.id == track.id;
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 20,
        color:
            isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        track.label,
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
      onTap: () {
        Navigator.pop(sheetContext);
        _vps.setAudioTrackOption(track);
      },
    );
  }

  Widget _speedChip(double speed, bool isDark) {
    final theme = Theme.of(context);
    final selected = _vps.playbackSpeed == speed;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _vps.changeSpeed(speed),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(
                    Icons.check,
                    size: 15,
                    color: theme.colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  '${speed}x',
                  style: TextStyle(
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Label shown for a stream in the quality menu: the resolution plus
  /// the container type that will actually play (mp4 / webm), e.g.
  /// `1080p (adaptive • webm)` or `360p (mp4)`.
  String _qualityLabel(VideoStreamInfo stream) {
    final container = stream.container.isEmpty
        ? (stream.format == 'muxed' ? 'mp4' : stream.format)
        : stream.container;
    final adaptive = stream.format == 'muxed' ? '' : ' adaptive •';
    return '${stream.quality} ($adaptive $container)'
        .replaceAll('  ', ' ')
        .replaceAll('( ', '(');
  }

  Widget _qualityRow(
      VideoStreamInfo stream, bool isDark, BuildContext sheetContext) {
    final isCurrent = _vps.currentStream != null &&
        stream.quality == _vps.currentStream!.quality &&
        stream.format == _vps.currentStream!.format;
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 20,
        color:
            isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        _qualityLabel(stream),
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
      onTap: () {
        Navigator.pop(sheetContext);
        _vps.changeQuality(stream);
      },
    );
  }

  // ─────────── Download sheet ───────────

  Future<void> _openDownloadSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final downloads = context.read<DownloadService>();
    final active = downloads.activeFor(widget.video.id);
    final completed =
        active == null ? downloads.playableFor(widget.video.id) : null;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                active != null
                    ? 'Downloading'
                    : completed != null
                        ? 'Downloaded'
                        : 'Download',
                style: TextStyle(
                  color: isDark ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (active != null) ...[
              _downloadingTile(active, isDark, sheetContext),
            ] else if (completed != null) ...[
              ListTile(
                leading: Icon(Icons.play_circle_fill,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Play downloaded copy'),
                subtitle: Text(
                  'Offline • ${completed.quality == 'Auto' ? 'best' : completed.quality} quality',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _replacing = true; // replacement pop is not a minimize
                  Navigator.pushReplacement(
                    context,
                    pushPlayerRoute(
                      PlayerScreen(
                        video: widget.video,
                        download: completed,
                      ),
                      animationsEnabled: context
                          .read<StorageService>()
                          .animationsEnabled,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Delete download'),
                subtitle:
                    const Text('Removes the saved files from this device'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(completed);
                },
              ),
            ] else ...[
              ListTile(
                leading: Icon(Icons.video_library,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Video + audio'),
                subtitle: const Text('Best quality with sound (adaptive if needed)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _chooseQualityAndDownload(DownloadType.videoAudio);
                },
              ),
              ListTile(
                leading: Icon(Icons.videocam,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Video only'),
                subtitle: const Text('Video track without audio'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _chooseQualityAndDownload(DownloadType.videoOnly);
                },
              ),
              ListTile(
                leading: Icon(Icons.audiotrack,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Audio only'),
                subtitle: const Text('Audio track (m4a/webm)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _chooseQualityAndDownload(DownloadType.audio);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Live progress + cancel for the in-flight download of this video.
  Widget _downloadingTile(
      DownloadItem active, bool isDark, BuildContext sheetContext) {
    return ListTile(
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.6),
      ),
      title: Text(
        active.progress > 0
            ? 'Downloading — ${(active.progress * 100).round()}%'
            : 'Downloading…',
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
      subtitle: Text(
        '${_formatBytes(active.receivedBytes)}'
        '${active.totalBytes > 0 ? ' / ${_formatBytes(active.totalBytes)}' : ''}',
      ),
      trailing: TextButton(
        onPressed: () {
          Navigator.pop(sheetContext);
          context.read<DownloadService>().cancel(active);
        },
        child: const Text('Cancel'),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text(
            'The saved files for "${item.title}" will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<DownloadService>().delete(item);
    }
  }

  Future<void> _chooseQualityAndDownload(DownloadType type) async {
    final downloads = context.read<DownloadService>();
    final messenger = ScaffoldMessenger.of(context);

    List<String> qualities;
    if (type == DownloadType.audio || type == DownloadType.music) {
      qualities = const ['Best'];
    } else {
      var streams = _vps.streams;
      if (streams.isEmpty) {
        try {
          streams = await _service.getAvailableStreams(widget.video.url);
        } catch (_) {
          streams = const [];
        }
      }
      qualities = downloads.availableQualities(streams, type);
      if (qualities.isEmpty) qualities = const ['Auto'];
    }
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Choose quality',
                style: TextStyle(
                  color: isDark ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            for (final quality in qualities)
              ListTile(
                dense: true,
                leading: Icon(
                  quality == 'Best' ? Icons.audiotrack : Icons.high_quality,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  quality == 'Auto'
                      ? 'Auto (recommended)'
                      : quality == 'Best'
                          ? 'Best available'
                          : quality,
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await downloads.startDownload(
                    video: widget.video,
                    type: type,
                    quality: quality,
                  );
                  messenger.showSnackBar(
                    const SnackBar(
                      content:
                          Text('Download started — see Library ▸ Downloads'),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─────────── Build ───────────

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final saved = storage.isVideoSaved(widget.video.id);

    // The page must react to playback-service state by itself — the old
    // code only rebuilt on unrelated setStates, so the body could stay on
    // the loading spinner forever while the video happily played above.
    final vpsLoading =
        context.select<VideoPlaybackService, bool>((v) => v.loading);
    final vpsError =
        context.select<VideoPlaybackService, String?>((v) => v.error);

    final animationsEnabled =
        context.select<StorageService, bool>((s) => s.animationsEnabled);

    Widget buildControls() => YouTubeVideoControls(
          player: _vps.player,
          isFullscreen: _isFullscreen,
          onToggleFullscreen: _toggleFullscreen,
          onOpenSettings: _openSettingsSheet,
          onSwipeDown: _onSwipeDown,
          animationsEnabled: animationsEnabled,
          fitMode: storage.videoFitMode,
          onCycleFit: _cycleVideoFit,
        );

    // How the video scales inside the player surface.
    final videoFit = switch (storage.videoFitMode) {
      'crop' => BoxFit.cover,
      'stretch' => BoxFit.fill,
      _ => BoxFit.contain,
    };

    // The player surface follows the selected fit mode (fit / crop /
    // stretch) — the same choice applies inline and in fullscreen.
    final video = Video(
      controller: _vps.controller,
      fit: videoFit,
      controls: (state) => buildControls(),
    );

    // PiP always letterboxes — crop/stretch would distort the tiny window.
    final pipVideo = Video(
      controller: _vps.controller,
      controls: (state) => buildControls(),
    );

    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          // Fullscreen = the whole screen: the video surface stretches
          // edge to edge and the selected fit mode decides how the picture
          // scales inside it (no more empty side bars from a forced 16:9
          // box on modern tall screens).
          body: video,
        ),
      );
    }

    final page = Scaffold(
      // The page follows the app theme (light / dark / pitch black) —
      // only the video surface itself stays black, like every player.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ColoredBox(
              color: Colors.black,
              child: AspectRatio(aspectRatio: 16 / 9, child: video),
            ),
          ),
          Expanded(child: _buildBody(storage, saved, vpsLoading, vpsError)),
        ],
      ),
    );

    final pipPage = Platform.isAndroid
        ? PipWidget(
            pipChild: ColoredBox(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  // Always letterboxed (contain) — crop/stretch would
                  // distort the tiny PiP window.
                  child: pipVideo,
                ),
              ),
            ),
            child: page,
          )
        : page;

    // The system back gesture also minimizes into the mini player.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // Only a genuine user back gesture minimizes — being replaced
        // by the next video (or the Now Playing screen) is not one.
        if (didPop && !_replacing) _vps.minimize();
      },
      child: pipPage,
    );
  }

  Widget _buildBody(
    StorageService storage,
    bool saved,
    bool vpsLoading,
    String? vpsError,
  ) {
    if (vpsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vpsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 60, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                vpsError,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _vps.open(
                  widget.video,
                  download: widget.download,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final video = widget.video;
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Video views live directly under the title (YouTube
              // style); the channel row below shows subscribers.
              if (video.viewCount != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${formatViews(video.viewCount)} views',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Action row: Save / Share / Download / PiP
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            children: [
              _actionPill(
                icon: saved ? Icons.bookmark : Icons.bookmark_border,
                label: saved ? 'Saved' : 'Save',
                highlight: saved,
                onTap: () => storage.toggleSavedVideo(video),
              ),
              // Dubbed videos get a dedicated audio-language button —
              // no need to hunt through the gear menu.
              _AudioLanguagePill(onTap: _openAudioSheet),
              _actionPill(
                icon: Icons.share,
                label: 'Share',
                onTap: () => Share.share(video.url),
              ),
              _DownloadActionPill(
                video: video,
                onTap: _openDownloadSheet,
              ),
              // Audio-only: the video track turns off on the same
              // player and the dedicated Now Playing takes over —
              // notification controls included. Live streams keep no
              // timeline, so they stay in the video player.
              if (!video.isLive)
                _actionPill(
                  icon: Icons.headphones_outlined,
                  label: 'Audio only',
                  highlight: _switchingToAudio,
                  loading: _switchingToAudio,
                  onTap: _startAudioOnly,
                ),
              if (Platform.isAndroid)
                _actionPill(
                  icon: Icons.picture_in_picture_alt,
                  label: 'PiP',
                  onTap: () async {
                    try {
                      await AndroidPIP().enterPipMode();
                    } catch (_) {}
                  },
                ),
            ],
          ),
        ),
        // Channel row with real avatar.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (video.uploaderUrl.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChannelScreen(
                            channel: ChannelItem(
                              url: video.uploaderUrl,
                              name: video.uploader,
                              thumbnailUrl: video.uploaderAvatarUrl,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      ChannelAvatar(
                        avatarUrl: video.uploaderAvatarUrl,
                        name: video.uploader,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.uploader,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            // Subscriber count under the channel name;
                            // the video's views moved under the title.
                            if (_subscriberCount != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${formatViews(_subscriberCount)} subscribers',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ] else if (_loadingChannelInfo) ...[
                              const SizedBox(height: 2),
                              Text(
                                '…',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SubscribeButton(
                channelUrl: video.uploaderUrl,
                channelName: video.uploader,
                thumbnail: video.uploaderAvatarUrl,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Related videos',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_loadingRelated)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_related.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No related videos',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _loadRelated(force: true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
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
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
    bool loading = false,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: highlight
            ? accent.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          // Explicit press + hover tint so every pill answers touches
          // and mouse-overs visibly, on top of the default ripple.
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.pressed)
                ? accent.withValues(alpha: 0.20)
                : states.contains(WidgetState.hovered)
                    ? accent.withValues(alpha: 0.12)
                    : null,
          ),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  Icon(icon,
                      size: 20,
                      color:
                          highlight ? accent : theme.colorScheme.onSurface),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: highlight ? accent : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated audio-language pill shown only on videos that actually carry
/// dubbed tracks. Shows the active language and glows red while a dub
/// (not the original) is selected.
class _AudioLanguagePill extends StatelessWidget {
  final VoidCallback onTap;

  const _AudioLanguagePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final vps = context.watch<VideoPlaybackService>();
    if (vps.audioTracks.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final current = vps.currentAudioTrack;
    final dubbed = !(current?.isOriginal ?? true);
    var label = 'Audio';
    final locale = current?.locale ?? '';
    if (locale.isNotEmpty) {
      label = locale.length <= 3
          ? locale.toUpperCase()
          : locale.substring(0, 3).toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: dubbed
            ? accent.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  size: 20,
                  color: dubbed ? accent : theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: dubbed ? accent : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Download pill that mirrors the live download state: a progress ring with
/// the percentage while downloading, a red "Downloaded" badge once the
/// files are on disk, and the normal download action otherwise.
class _DownloadActionPill extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const _DownloadActionPill({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final active = downloads.activeFor(video.id);
    final done = active == null && downloads.isDownloaded(video.id);

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final highlight = active != null || done;
    final label = active != null
        ? (active.progress > 0 ? '${(active.progress * 100).round()}%' : '…')
        : done
            ? 'Downloaded'
            : 'Download';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: highlight
            ? accent.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                if (active != null)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: active.progress > 0 ? active.progress : null,
                      strokeWidth: 2.4,
                      color: accent,
                    ),
                  )
                else
                  Icon(
                    done ? Icons.download_done : Icons.download_outlined,
                    size: 20,
                    color: highlight ? accent : theme.colorScheme.onSurface,
                  ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: highlight ? accent : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
