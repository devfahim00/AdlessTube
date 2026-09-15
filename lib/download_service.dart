import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'newpipe_service.dart';

/// Manages video/music downloads: resolves streams, streams bytes to disk
/// with live progress, and persists metadata so the Downloads screen can
/// list everything in one place.
class DownloadService extends ChangeNotifier {
  static const _downloadsBox = 'downloads';
  final NewPipeService _service = NewPipeService();
  final Set<String> _cancelled = {};

  Box get _box => Hive.box(_downloadsBox);

  // ─────────── Queries ───────────

  List<DownloadItem> getAll() {
    final items = _box.values
        .map((e) => DownloadItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<DownloadItem> getVideos() => getAll()
      .where((item) =>
          item.type == DownloadType.videoAudio ||
          item.type == DownloadType.videoOnly)
      .toList();

  List<DownloadItem> getMusic() =>
      getAll().where((item) => item.isMusic).toList();

  bool isDownloaded(String videoId) =>
      getAll().any((item) => item.videoId == videoId && item.isCompleted);

  /// Best playable local copy for a video (prefers formats with audio).
  DownloadItem? playableFor(String videoId) {
    final completed =
        getAll().where((item) => item.videoId == videoId && item.isCompleted);
    for (final type in DownloadType.values) {
      for (final item in completed) {
        if (item.type == type &&
            (item.videoPath != null || item.audioPath != null)) {
          return item;
        }
      }
    }
    return null;
  }

  /// Distinct quality labels the user can pick for a download type.
  List<String> availableQualities(
    List<VideoStreamInfo> streams,
    DownloadType type,
  ) {
    final relevant = type == DownloadType.videoOnly
        ? streams.where((s) => s.format != 'muxed').toList()
        : streams;
    final qualities = relevant.map((s) => s.quality).toSet().toList()
      ..sort((a, b) => _rank(b).compareTo(_rank(a)));
    return ['Auto', ...qualities];
  }

  // ─────────── Actions ───────────

  Future<void> startDownload({
    required VideoItem video,
    required DownloadType type,
    String quality = 'Auto',
  }) async {
    final id = '${video.id}_${type.name}';
    _cancelled.remove(id);

    final existing = _box.get(id);
    if (existing is Map && existing['status'] == 'downloading') return;
    if (existing is Map) {
      _deleteFiles(DownloadItem.fromMap(Map<String, dynamic>.from(existing)));
    }

    final item = DownloadItem(
      id: id,
      videoId: video.id,
      title: video.title,
      uploader: video.uploader,
      thumbnailUrl: video.thumbnailUrl,
      videoUrl: video.url,
      type: type,
      quality: quality,
      status: 'downloading',
    );
    await _box.put(id, item.toMap());
    notifyListeners();
    unawaited(_run(item));
  }

  Future<void> cancel(DownloadItem item) async {
    _cancelled.add(item.id);
    await _box.delete(item.id);
    _deleteFiles(item);
    notifyListeners();
  }

  Future<void> delete(DownloadItem item) async {
    _cancelled.add(item.id);
    await _box.delete(item.id);
    _deleteFiles(item);
    notifyListeners();
  }

  // ─────────── Internals ───────────

  DownloadItem? _read(String id) {
    final value = _box.get(id);
    if (value is Map) {
      return DownloadItem.fromMap(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Future<String> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  void _deleteFiles(DownloadItem item) {
    for (final path in [item.videoPath, item.audioPath]) {
      if (path == null) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _updateProgress(
    String id, {
    int? received,
    int? total,
  }) async {
    final fresh = _read(id);
    if (fresh == null) return;
    await _box.put(
      id,
      fresh
          .copyWith(
            receivedBytes: received ?? fresh.receivedBytes,
            totalBytes: total ?? fresh.totalBytes,
          )
          .toMap(),
    );
    notifyListeners();
  }

  Future<void> _finish(
    String id, {
    String? videoPath,
    String? audioPath,
    required int totalBytes,
    required String status,
  }) async {
    final fresh = _read(id);
    if (fresh == null) return;
    await _box.put(
      id,
      fresh
          .copyWith(
            videoPath: videoPath,
            audioPath: audioPath,
            totalBytes: totalBytes,
            receivedBytes: totalBytes,
            status: status,
          )
          .toMap(),
    );
    notifyListeners();
  }

  Future<void> _run(DownloadItem item) async {
    try {
      final dir = await _dir();

      // ── Audio only (music player + video player audio option) ──
      if (item.isMusic || item.type == DownloadType.audio) {
        final audio = await _service.getBestAudioStream(item.videoUrl);
        if (audio == null) throw StateError('No audio stream found.');
        final path =
            '$dir/${item.videoId}_audio.${_extFor(audio.format, audio: true)}';
        await _downloadFile(
          audio.url,
          path,
          itemId: item.id,
          onProgress: (received, total) =>
              _updateProgress(item.id, received: received, total: total),
        );
        final size = File(path).lengthSync();
        await _finish(item.id,
            audioPath: path, totalBytes: size, status: 'completed');
        return;
      }

      final streams = await _service.getAvailableStreams(item.videoUrl);
      if (streams.isEmpty) throw StateError('No streams found.');

      final target = item.quality == 'Auto'
          ? null
          : int.tryParse(item.quality.replaceAll('p', ''));

      // ── Video only (no sound) ──
      if (item.type == DownloadType.videoOnly) {
        final adaptive = streams.where((s) => s.format != 'muxed').toList();
        final stream = _pick(adaptive, target);
        if (stream == null) throw StateError('No video stream found.');
        final path =
            '$dir/${item.videoId}_${stream.quality}_video.${_extFor(stream.format, audio: false)}';
        await _downloadFile(
          stream.url,
          path,
          itemId: item.id,
          onProgress: (received, total) =>
              _updateProgress(item.id, received: received, total: total),
        );
        final size = File(path).lengthSync();
        await _finish(item.id,
            videoPath: path, totalBytes: size, status: 'completed');
        return;
      }

      // ── Video + audio ──
      // Prefer a single muxed file; otherwise pair the adaptive video with
      // its audio track and store both paths together.
      final muxed = streams.where((s) => s.format == 'muxed').toList();
      final muxedPick = _pick(muxed, target);
      if (muxedPick != null) {
        final path =
            '$dir/${item.videoId}_${muxedPick.quality}_muxed.${_extFor(muxedPick.format, audio: false)}';
        await _downloadFile(
          muxedPick.url,
          path,
          itemId: item.id,
          onProgress: (received, total) =>
              _updateProgress(item.id, received: received, total: total),
        );
        final size = File(path).lengthSync();
        await _finish(item.id,
            videoPath: path, totalBytes: size, status: 'completed');
        return;
      }

      final adaptive = streams
          .where((s) => s.format != 'muxed' && (s.audioUrl ?? '').isNotEmpty)
          .toList();
      final stream = _pick(adaptive, target);
      if (stream == null) throw StateError('No video stream found.');
      final audioUrl = stream.audioUrl!;
      final videoPath =
          '$dir/${item.videoId}_${stream.quality}_video.${_extFor(stream.format, audio: false)}';
      final audioPath = '$dir/${item.videoId}_audio.m4a';

      await _downloadFile(
        stream.url,
        videoPath,
        itemId: item.id,
        onProgress: (received, total) =>
            _updateProgress(item.id, received: received, total: total),
      );
      final videoBytes = File(videoPath).lengthSync();
      await _updateProgress(item.id, received: videoBytes, total: 0);
      await _downloadFile(
        audioUrl,
        audioPath,
        itemId: item.id,
        onProgress: (received, _) =>
            _updateProgress(item.id, received: videoBytes + received, total: 0),
      );
      final totalBytes = videoBytes + File(audioPath).lengthSync();
      await _finish(item.id,
          videoPath: videoPath,
          audioPath: audioPath,
          totalBytes: totalBytes,
          status: 'completed');
    } catch (e) {
      if (_cancelled.contains(item.id)) return;
      debugPrint('Download failed: $e');
      final fresh = _read(item.id);
      if (fresh != null) {
        await _finish(item.id,
            videoPath: null, audioPath: null, totalBytes: 0, status: 'failed');
      }
    }
  }

  /// Streams [url] to [savePath] while reporting progress.
  /// Partial files are removed when the download fails or is cancelled.
  Future<void> _downloadFile(
    String url,
    String savePath, {
    required String itemId,
    required void Function(int received, int total) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final total = response.contentLength; // -1 when unknown
      sink = File(savePath).openWrite();
      var received = 0;
      var lastTick = 0;
      await for (final chunk in response) {
        if (_cancelled.contains(itemId)) throw StateError('cancelled');
        sink.add(chunk);
        received += chunk.length;
        if (received - lastTick >= 200 * 1024) {
          lastTick = received;
          onProgress(received, total > 0 ? total : 0);
        }
      }
      await sink.flush();
      await sink.close();
      onProgress(received, total > 0 ? total : 0);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        final file = File(savePath);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Highest-quality stream at or below [target] (streams are sorted
  /// best-first). Falls back to the lowest available when everything is
  /// above the target.
  VideoStreamInfo? _pick(List<VideoStreamInfo> streams, int? target) {
    if (streams.isEmpty) return null;
    if (target == null) return streams.first;
    final atOrBelow =
        streams.where((s) => _rank(s.quality) <= target).toList();
    if (atOrBelow.isNotEmpty) return atOrBelow.first;
    return streams.last;
  }

  int _rank(String quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  String _extFor(String format, {required bool audio}) {
    final f = format.toLowerCase();
    if (f.contains('webm')) return 'webm';
    if (f.contains('m4a')) return 'm4a';
    if (f.contains('mp4') || f.contains('mpeg4')) return 'mp4';
    if (f.contains('3gp')) return '3gp';
    return audio ? 'm4a' : 'mp4';
  }
}
