import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';

class StorageService extends ChangeNotifier {
  static const _historyBox = 'history';
  static const _likedSongsBox = 'liked_songs';
  static const _subscriptionsBox = 'subscriptions';
  static const _settingsBox = 'settings';
  static const _playbackBox = 'playback';
  static const _regionKey = 'region_code';
  static const _regionSelectedKey = 'region_selected';
  static const _themeModeKey = 'theme_mode';
  static const _defaultQualityKey = 'default_quality';
  static const _musicAutoplayKey = 'music_autoplay';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_historyBox);
    await Hive.openBox(_likedSongsBox);
    await Hive.openBox(_subscriptionsBox);
    await Hive.openBox(_settingsBox);
    await Hive.openBox(_playbackBox);
  }

  // ─────────── Region ───────────
  bool get hasSelectedRegion =>
      Hive.box(_settingsBox).get(_regionSelectedKey, defaultValue: false);

  String get regionCode =>
      Hive.box(_settingsBox).get(_regionKey, defaultValue: 'US');

  Future<void> setRegion(String code) async {
    await Hive.box(_settingsBox).put(_regionKey, code);
    await Hive.box(_settingsBox).put(_regionSelectedKey, true);
    notifyListeners();
  }

  // ─────────── History ───────────
  Future<void> addToHistory(VideoItem video) async {
    await Hive.box(_historyBox).put(video.id, video.toMap());
    notifyListeners();
  }

  List<VideoItem> getHistory() {
    return Hive.box(_historyBox)
        .values
        .map((e) => VideoItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> clearHistory() async {
    await Hive.box(_historyBox).clear();
    notifyListeners();
  }

  // ─────────────────── Liked songs ───────────────────
  List<VideoItem> getLikedSongs() {
    return Hive.box(_likedSongsBox)
        .values
        .map((e) => VideoItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();
  }

  bool isSongLiked(String videoId) =>
      Hive.box(_likedSongsBox).containsKey(videoId);

  Future<void> toggleLikedSong(VideoItem song) async {
    final box = Hive.box(_likedSongsBox);
    if (box.containsKey(song.id)) {
      await box.delete(song.id);
    } else {
      await box.put(song.id, song.toMap());
    }
    notifyListeners();
  }

  ThemeMode get themeMode {
    final value = Hive.box(_settingsBox).get(_themeModeKey, defaultValue: 'auto');
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'auto',
    };
    await Hive.box(_settingsBox).put(_themeModeKey, value);
    notifyListeners();
  }

  String get defaultQuality => Hive.box(_settingsBox)
      .get(_defaultQualityKey, defaultValue: 'Auto') as String;

  Future<void> setDefaultQuality(String quality) async {
    await Hive.box(_settingsBox).put(_defaultQualityKey, quality);
    notifyListeners();
  }

  bool get musicAutoplay => Hive.box(_settingsBox)
      .get(_musicAutoplayKey, defaultValue: true) as bool;

  Future<void> setMusicAutoplay(bool enabled) async {
    await Hive.box(_settingsBox).put(_musicAutoplayKey, enabled);
    notifyListeners();
  }

  Map<String, dynamic>? getPlaybackState(String videoId) {
    final value = Hive.box(_playbackBox).get(videoId);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> savePlaybackState({
    required String videoId,
    required Duration position,
    required String quality,
    required String format,
  }) {
    return Hive.box(_playbackBox).put(videoId, {
      'positionMs': position.inMilliseconds,
      'quality': quality,
      'format': format,
    });
  }

  // ─────────── Subscriptions ───────────
  /// Channel name → subscription info map
  Map<String, Map<String, dynamic>> getSubscriptions() {
    final box = Hive.box(_subscriptionsBox);
    return {
      for (var key in box.keys)
        key.toString(): Map<String, dynamic>.from(box.get(key)),
    };
  }

  bool isSubscribed(String channelUrl) {
    return Hive.box(_subscriptionsBox).containsKey(channelUrl);
  }

  Future<void> subscribe({
    required String channelUrl,
    required String channelName,
    String thumbnail = '',
  }) async {
    await Hive.box(_subscriptionsBox).put(channelUrl, {
      'name': channelName,
      'thumbnail': thumbnail,
      'subscribedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> unsubscribe(String channelUrl) async {
    await Hive.box(_subscriptionsBox).delete(channelUrl);
    notifyListeners();
  }

  Future<void> toggleSubscribe({
    required String channelUrl,
    required String channelName,
    String thumbnail = '',
  }) async {
    if (isSubscribed(channelUrl)) {
      await unsubscribe(channelUrl);
    } else {
      await subscribe(
        channelUrl: channelUrl,
        channelName: channelName,
        thumbnail: thumbnail,
      );
    }
  }

  List<String> getSubscribedChannelUrls() =>
      Hive.box(_subscriptionsBox).keys.map((e) => e.toString()).toList();

  List<String> getSubscribedChannelNames() => Hive.box(_subscriptionsBox)
      .values
      .map((e) => (e as Map)['name'].toString())
      .toList();
}
