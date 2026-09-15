import 'dart:async';
import 'dart:io';

import 'package:android_pip/android_pip.dart';
import 'package:android_pip/pip_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../download_service.dart';
import '../models.dart';
import '../music_playback_service.dart';
import '../newpipe_service.dart';
import '../storage_service.dart';
import '../widgets.dart';
import 'channel_screen.dart';
import 'video_controls.dart';

/// ═══════════════════════ PLAYER ═══════════════════════
///
/// YouTube-style player:
/// * video area with custom controls (tap to pause, double-tap to seek,
///   gear menu with quality + playback speed, fullscreen),
/// * action row under the title with Save / Share / Download / PiP,
/// * related videos below.
class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  /// When set, playback uses the local downloaded files instead of network.
  final DownloadItem? download;

  const PlayerScreen({super.key, required this.video, this.download});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  late final StorageService _storage;
  final _service = NewPipeService();

  bool _loading = true;
  String? _error;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  bool _isLeaving = false;

  List<VideoStreamInfo> _streams = [];
  VideoStreamInfo? _currentStream;
  List<VideoItem> _related = [];
  bool _loadingRelated = false;
  Duration _lastSavedPosition = Duration.zero;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    unawaited(context.read<MusicPlaybackService>().stop());
    _player = Player();
    _controller = VideoController(_player);
    WidgetsBinding.instance.addObserver(this);

    _player.stream.playing.listen((playing) {
      // Persist immediately when the user pauses, instead of waiting for the
      // periodic position listener. This also covers an immediate app close.
      if (!playing &&
          !_loading &&
          _player.state.position.inMilliseconds > 0) {
        _savePlaybackState();
      }
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.position.listen((position) {
      if ((position - _lastSavedPosition).inSeconds >= 5) {
        _savePlaybackState(position);
      }
    });

    _loadStreams();
    _loadRelated();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  Future<void> _loadStreams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final download = widget.download;
      if (download != null) {
        final videoPath = download.videoPath;
        if (videoPath == null || !File(videoPath).existsSync()) {
          setState(() {
            _error = 'The downloaded file is missing.';
            _loading = false;
          });
          return;
        }
        final saved = _storage.getPlaybackState(widget.video.id);
        final savedPosition = Duration(
          milliseconds: (saved?['positionMs'] as int?) ?? 0,
        );
        await _player.open(Media(videoPath, start: savedPosition));
        final audioPath = download.audioPath;
        if (audioPath != null && File(audioPath).existsSync()) {
          await _player.setAudioTrack(
            AudioTrack.uri(Uri.file(audioPath).toString()),
          );
        }
        await _player.play();
        setState(() => _loading = false);
        return;
      }

      final streams = await _service.getAvailableStreams(widget.video.url);
      if (streams.isEmpty) {
        setState(() {
          _error = 'No playable stream found.';
          _loading = false;
        });
        return;
      }
      final saved = _storage.getPlaybackState(widget.video.id);
      final savedQuality = saved?['quality'];
      final savedFormat = saved?['format'];
      final preferredQuality = _storage.defaultQuality;
      final savedPosition = Duration(
        milliseconds: (saved?['positionMs'] as int?) ?? 0,
      );
      _streams = streams;
      _currentStream = _selectDefaultStream(streams, preferredQuality);
      for (final stream in streams) {
        if (stream.quality == savedQuality && stream.format == savedFormat) {
          _currentStream = stream;
          break;
        }
      }
      await _openStream(_currentStream!, start: savedPosition);
      await _player.play();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadRelated() async {
    setState(() => _loadingRelated = true);
    try {
      final rel = await _service.getRelatedVideos(widget.video.url);
      if (mounted) {
        setState(() => _related = rel.where((v) => !v.isLive).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRelated = false);
  }

  Future<void> _changeQuality(VideoStreamInfo stream) async {
    final wasPlaying = _isPlaying;
    final position = _player.state.position;
    await _openStream(stream, start: position);
    if (wasPlaying) {
      await _player.play();
    } else {
      await _player.pause();
    }
    setState(() => _currentStream = stream);
    _savePlaybackState(position);
  }

  VideoStreamInfo _selectDefaultStream(
    List<VideoStreamInfo> streams,
    String preference,
  ) {
    // "Auto" uses a connection-friendly 720p target instead of always
    // starting the most bandwidth-intensive stream.
    final target = preference == 'Auto'
        ? 720
        : int.tryParse(preference.replaceAll('p', '')) ?? 720;
    final ranked = streams
        .map((stream) => (stream: stream, rank: _qualityRank(stream.quality)))
        .where((item) => item.rank > 0)
        .toList();
    final atOrBelowTarget =
        ranked.where((item) => item.rank <= target).toList();
    if (atOrBelowTarget.isNotEmpty) return atOrBelowTarget.first.stream;
    return ranked.isNotEmpty ? ranked.last.stream : streams.first;
  }

  int _qualityRank(String quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  Future<void> _changeSpeed(double speed) async {
    await _player.setRate(speed);
    if (mounted) setState(() => _playbackSpeed = speed);
  }

  Future<void> _openStream(VideoStreamInfo stream, {Duration? start}) async {
    await _player.open(Media(stream.url, start: start));
    if (stream.audioUrl != null) {
      await _player.setAudioTrack(AudioTrack.uri(stream.audioUrl!));
    }
  }

  void _savePlaybackState([Duration? position]) {
    if (widget.download != null) return; // local files keep no stream state
    final stream = _currentStream;
    if (stream == null) return;
    final currentPosition = position ?? _player.state.position;
    _lastSavedPosition = currentPosition;
    unawaited(_storage.savePlaybackState(
      videoId: widget.video.id,
      position: currentPosition,
      quality: stream.quality,
      format: stream.format,
    ));
  }

  void _openRelated(VideoItem v) async {
    final storage = context.read<StorageService>();
    await storage.addToHistory(v);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(video: v)),
    );
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savePlaybackState();
    unawaited(_player.stop());
    unawaited(_player.dispose());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _stopBeforeLeaving() async {
    _savePlaybackState();
    await _player.stop();
  }

  // ─────────── Settings (gear) sheet ───────────

  static const _speeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  Future<void> _openSettingsSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : null,
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
                leading: const Icon(Icons.download_done, color: Colors.red),
                title: Text(
                  'Playing downloaded file (${widget.download!.quality})',
                  style: TextStyle(color: isDark ? Colors.white : null),
                ),
              )
            else if (_streams.isEmpty)
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
                    for (final stream in _streams)
                      _qualityRow(stream, isDark, sheetContext),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _speedChip(double speed, bool isDark) {
    final selected = _playbackSpeed == speed;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _changeSpeed(speed),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.red : Colors.white12,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${speed}x',
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black54),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _qualityRow(
      VideoStreamInfo stream, bool isDark, BuildContext sheetContext) {
    final isCurrent = _currentStream != null &&
        stream.quality == _currentStream!.quality &&
        stream.format == _currentStream!.format;
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 20,
        color: isCurrent ? Colors.red : null,
      ),
      title: Text(
        '${stream.quality}${stream.format == 'muxed' ? '' : ' (adaptive)'}',
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
      onTap: () {
        Navigator.pop(sheetContext);
        _changeQuality(stream);
      },
    );
  }

  // ─────────── Download sheet ───────────

  Future<void> _openDownloadSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : null,
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
                'Download',
                style: TextStyle(
                  color: isDark ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.red),
              title: const Text('Video + audio'),
              subtitle: const Text('Best quality with sound (adaptive if needed)'),
              onTap: () {
                Navigator.pop(sheetContext);
                _chooseQualityAndDownload(DownloadType.videoAudio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.red),
              title: const Text('Video only'),
              subtitle: const Text('Video track without audio'),
              onTap: () {
                Navigator.pop(sheetContext);
                _chooseQualityAndDownload(DownloadType.videoOnly);
              },
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack, color: Colors.red),
              title: const Text('Audio only'),
              subtitle: const Text('Audio track (m4a/webm)'),
              onTap: () {
                Navigator.pop(sheetContext);
                _chooseQualityAndDownload(DownloadType.audio);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseQualityAndDownload(DownloadType type) async {
    final downloads = context.read<DownloadService>();
    final messenger = ScaffoldMessenger.of(context);

    List<String> qualities;
    if (type == DownloadType.audio || type == DownloadType.music) {
      qualities = const ['Best'];
    } else {
      var streams = _streams;
      if (streams.isEmpty) {
        try {
          streams = await _service.getAvailableStreams(widget.video.url);
        } catch (_) {
          streams = const [];
        }
        if (mounted) setState(() => _streams = streams);
      }
      qualities = downloads.availableQualities(streams, type);
      if (qualities.isEmpty) qualities = const ['Auto'];
    }
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : null,
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
                  color: Colors.red,
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

    final video = Video(
      controller: _controller,
      controls: (state) => YouTubeVideoControls(
        player: _player,
        isFullscreen: _isFullscreen,
        onBack: _isFullscreen
            ? _exitFullscreen
            : () => Navigator.of(context).maybePop(),
        onToggleFullscreen: _toggleFullscreen,
        onOpenSettings: _openSettingsSheet,
      ),
    );

    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: video),
          ),
        ),
      );
    }

    final page = Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: video,
            ),
          ),
          Expanded(child: _buildBody(storage, saved)),
        ],
      ),
    );

    final pipPage = Platform.isAndroid
        ? PipWidget(
            pipChild: ColoredBox(
              color: Colors.black,
              child: Center(
                child: AspectRatio(aspectRatio: 16 / 9, child: video),
              ),
            ),
            child: page,
          )
        : page;

    final navigator = Navigator.of(context);
    return PopScope(
      canPop: _isLeaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_isLeaving) {
          setState(() => _isLeaving = true);
          await _stopBeforeLeaving();
          if (mounted) {
            navigator.pop();
          }
        }
      },
      child: pipPage,
    );
  }

  Widget _buildBody(StorageService storage, bool saved) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadStreams,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final video = widget.video;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            video.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
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
              _actionPill(
                icon: Icons.share,
                label: 'Share',
                onTap: () => Share.share(video.url),
              ),
              _actionPill(
                icon: Icons.download_outlined,
                label: 'Download',
                onTap: _openDownloadSheet,
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
        // Channel row
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
                              thumbnailUrl: video.thumbnailUrl,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.uploader,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (video.viewCount != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${formatViews(video.viewCount)} views',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SubscribeButton(
                channelUrl: video.uploaderUrl,
                channelName: video.uploader,
                thumbnail: video.thumbnailUrl,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.grey, height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Related videos',
            style: TextStyle(
              color: Colors.white,
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
            padding: const EdgeInsets.all(16),
            child: Text(
              'No related videos',
              style: TextStyle(color: Colors.grey[600]),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: highlight
            ? Colors.red.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(icon,
                    size: 20, color: highlight ? Colors.red : Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: highlight ? Colors.red : Colors.white,
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
