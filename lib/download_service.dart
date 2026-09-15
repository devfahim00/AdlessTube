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

      // Video and audio download in parallel on separate connections —
      // roughly twice as fast as one after the other on most networks.
      var videoReceived = 0;
      var audioReceived = 0;
      var videoTotal = 0;
      var audioTotal = 0;
      var lastPairTick = 0;
      void reportPair() {
        final received = videoReceived + audioReceived;
        if (received - lastPairTick >= 400 * 1024) {
          lastPairTick = received;
          _updateProgress(
            item.id,
            received: received,
            total: videoTotal > 0 && audioTotal > 0
                ? videoTotal + audioTotal
                : 0,
          );
        }
      }

      await Future.wait<void>([
        _downloadFile(
          stream.url,
          videoPath,
          itemId: item.id,
          onProgress: (received, total) {
            videoReceived = received;
            videoTotal = total;
            reportPair();
          },
        ),
        _downloadFile(
          audioUrl,
          audioPath,
          itemId: item.id,
          onProgress: (received, total) {
            audioReceived = received;
            audioTotal = total;
            reportPair();
          },
        ),
      ]);
      final totalBytes = File(videoPath).lengthSync() +
          File(audioPath).lengthSync();
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

  // ─────────── Fast download core ───────────

  /// Files below this size go over a single connection — parallel
  /// segments would only add overhead.
  static const _minParallelBytes = 2 * 1024 * 1024; // 2 MB

  /// Downloads [url] to [savePath] as fast as the server allows.
  ///
  /// Large files are split into segments downloaded over parallel HTTP
  /// range connections (the YouTube CDN supports them), typically several
  /// times faster than a single stream. Anything the server can't
  /// range-serve falls back to one plain connection.
  Future<void> _downloadFile(
    String url,
    String savePath, {
    required String itemId,
    required void Function(int received, int total) onProgress,
  }) async {
    var total = -1;
    try {
      total = await _probeContentLength(url);
    } catch (_) {}
    if (total >= _minParallelBytes) {
      try {
        await _downloadParallel(url, savePath, total, itemId, onProgress);
        return;
      } catch (e) {
        if (_cancelled.contains(itemId)) rethrow;
        debugPrint('Parallel download fell back to single: $e');
        _quietDelete(savePath);
      }
    }
    await _downloadSingle(url, savePath, itemId: itemId, onProgress: onProgress);
  }

  /// Asks the server for one byte and reads the full size from the
  /// `Content-Range` header. Returns -1 when ranges are not supported.
  Future<int> _probeContentLength(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close();
      final status = response.statusCode;
      final contentRange = response.headers.value('Content-Range') ?? '';
      if (status == 206 && contentRange.contains('/')) {
        // The tiny 1-byte body is drained so the socket is released.
        await response.drain<void>();
        final total = int.tryParse(contentRange.split('/').last);
        if (total != null && total > 0) return total;
      }
      return -1;
    } finally {
      // Never let the probe stream a full body — abandon the connection.
      client.close(force: true);
    }
  }

  /// Splits [total] bytes into 3-8 segments of at least 256 KB.
  List<(int, int)> _planSegments(int total) {
    var count = total >= 128 * 1024 * 1024
        ? 8
        : total >= 32 * 1024 * 1024
            ? 6
            : total >= 8 * 1024 * 1024
                ? 4
                : 3;
    final bySize = total ~/ (256 * 1024);
    if (bySize < count) count = bySize;
    if (count < 1) count = 1;
    final segments = <(int, int)>[];
    final size = total ~/ count;
    var start = 0;
    for (var i = 0; i < count; i++) {
      final end = i == count - 1 ? total - 1 : start + size - 1;
      segments.add((start, end));
      start = end + 1;
    }
    return segments;
  }

  /// One parallel segment writer: its own positioned handle into the
  /// shared, pre-allocated target file.
  Future<void> _downloadSegment(
    String url,
    RandomAccessFile raf,
    int start,
    int end,
    String itemId,
    void Function(int chunkBytes) onChunk,
  ) async {
    var offset = start;
    var attempt = 0;
    while (offset <= end) {
      attempt++;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-$end');
        final response = await request.close();
        if (response.statusCode != 206) {
          throw StateError('HTTP ${response.statusCode}');
        }
        await raf.setPosition(offset);
        await for (final chunk in response) {
          if (_cancelled.contains(itemId)) throw StateError('cancelled');
          await raf.writeFrom(chunk);
          offset += chunk.length;
          onChunk(chunk.length);
        }
        if (offset != end + 1) {
          throw StateError('Segment incomplete ($offset/${end + 1})');
        }
        return;
      } catch (e) {
        if (_cancelled.contains(itemId) || attempt >= 3) rethrow;
        debugPrint('Segment retry $attempt ($start-$end): $e');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        // Loop continues from the confirmed offset — dropped connections
        // resume exactly where they stopped instead of restarting the file.
      } finally {
        // Single-use client: abandon the connection instead of waiting
        // for a possibly dead socket to clean up on its own.
        client.close(force: true);
      }
    }
  }

  Future<void> _downloadParallel(
    String url,
    String savePath,
    int total,
    String itemId,
    void Function(int received, int total) onProgress,
  ) async {
    final segments = _planSegments(total);

    // Create the target file, then open every segment handle BEFORE the
    // first byte is written: each FileMode.write open truncates an empty
    // file (harmless), and afterwards each handle writes its own range.
    final handles = <RandomAccessFile>[];
    try {
      final init = await File(savePath).open(mode: FileMode.write);
      // Pre-allocating keeps the filesystem from fragmenting 8 writers.
      await init.truncate(total);
      await init.close();
      for (var i = 0; i < segments.length; i++) {
        handles.add(await File(savePath).open(mode: FileMode.write));
      }

      var received = 0;
      var lastTick = 0;
      void report(int chunk) {
        received += chunk;
        if (received - lastTick >= 500 * 1024) {
          lastTick = received;
          onProgress(received, total);
        }
      }

      await Future.wait<void>([
        for (var i = 0; i < segments.length; i++)
          _downloadSegment(
            url,
            handles[i],
            segments[i].$1,
            segments[i].$2,
            itemId,
            report,
          ),
      ]);
      onProgress(total, total);
    } finally {
      for (final handle in handles) {
        try {
          await handle.close();
        } catch (_) {}
      }
    }
  }

  /// Plain single-connection download — the fallback path.
  Future<void> _downloadSingle(
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
      if (response.statusCode != 200 && response.statusCode != 206) {
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
      _quietDelete(savePath);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _quietDelete(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
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
