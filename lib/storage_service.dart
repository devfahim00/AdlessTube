import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';
import 'user_profile_service.dart';

class StorageService extends ChangeNotifier {
  static const _historyBox = 'history';
  static const _likedSongsBox = 'liked_songs';
  static const _subscriptionsBox = 'subscriptions';
  static const _settingsBox = 'settings';
  static const _playbackBox = 'playback';
  static const _savedVideosBox = 'saved_videos';
  static const _downloadsBoxName = 'downloads';
  static const _searchHistoryBox = 'search_history';
  static const _regionKey = 'region_code';
  static const _regionSelectedKey = 'region_selected';
  static const _themeModeKey = 'theme_mode';
  static const _themeOptionKey = 'theme_option';
  static const _accentColorKey = 'accent_color';
  static const _videoFitKey = 'video_fit';
  static const _defaultQualityKey = 'default_quality';
  static const _musicAutoplayKey = 'music_autoplay';
  static const _preferredAudioLocaleKey = 'preferred_audio_locale';
  static const _servicesSelectedKey = 'services_selected';
  static const _enabledServicesKey = 'enabled_services';
  static const _shownFeedKey = 'shown_feed_ids';
  static const _animationsEnabledKey = 'animations_enabled';
  static const _lastAudioSessionKey = 'last_audio_session';

  /// Box names included in a backup export / import.
  ///
  /// The recommendation-profile boxes (watch events, feedback signals,
  /// channel affinity, topic weights) are part of every backup, so a
  /// restored device continues with the same personalized feed instead
  /// of rebuilding the user profile from zero.
  static const _backupBoxes = [
    _historyBox,
    _likedSongsBox,
    _subscriptionsBox,
    _settingsBox,
    _playbackBox,
    _savedVideosBox,
    _searchHistoryBox,
    UserProfileService.watchEventsBox,
    UserProfileService.signalsBox,
    UserProfileService.channelAffinityBox,
    UserProfileService.topicProfileBox,
  ];

  /// How many recently shown feed videos are remembered — pull-to-refresh
  /// skips these so the feed genuinely changes between refreshes.
  static const _shownFeedLimit = 250;

  /// Available service keys
  static const serviceYoutube = 'youtube';
  static const serviceShorts = 'shorts';
  static const serviceMusic = 'music';

  /// Valid [themeOption] values.
  static const themeOptions = ['auto', 'light', 'dark', 'black'];

  /// Valid [videoFitMode] values.
  static const videoFitModes = ['fit', 'crop', 'stretch'];

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_historyBox);
    await Hive.openBox(_likedSongsBox);
    await Hive.openBox(_subscriptionsBox);
    await Hive.openBox(_settingsBox);
    await Hive.openBox(_playbackBox);
    await Hive.openBox(_savedVideosBox);
    await Hive.openBox(_downloadsBoxName);
    await Hive.openBox(_searchHistoryBox);
    // Recommendation-profile boxes (opened here so export/import can
    // always reach them; the profile service opens them too, and Hive
    // returns the same instance for repeated opens).
    await Hive.openBox(UserProfileService.watchEventsBox);
    await Hive.openBox(UserProfileService.signalsBox);
    await Hive.openBox(UserProfileService.channelAffinityBox);
    await Hive.openBox(UserProfileService.topicProfileBox);
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

  // ─────────── Services (YouTube / Shorts / Music) ───────────
  bool get hasSelectedServices =>
      Hive.box(_settingsBox).get(_servicesSelectedKey, defaultValue: false);

  /// Returns the set of enabled service keys. Defaults to all three.
  Set<String> get enabledServices {
    final raw = Hive.box(_settingsBox).get(_enabledServicesKey);
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toSet();
    }
    // Default: everything enabled (for existing users)
    return {serviceYoutube, serviceShorts, serviceMusic};
  }

  bool isServiceEnabled(String service) => enabledServices.contains(service);

  Future<void> setEnabledServices(Set<String> services) async {
    // Always keep at least one service
    final safe = services.isEmpty
        ? {serviceYoutube}
        : services;
    await Hive.box(_settingsBox).put(_enabledServicesKey, safe.toList());
    await Hive.box(_settingsBox).put(_servicesSelectedKey, true);
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

  // ─────────────────── Saved videos (bookmark) ───────────────────
  List<VideoItem> getSavedVideos() {
    return Hive.box(_savedVideosBox)
        .values
        .map((e) => VideoItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();
  }

  bool isVideoSaved(String videoId) =>
      Hive.box(_savedVideosBox).containsKey(videoId);

  Future<void> toggleSavedVideo(VideoItem video) async {
    final box = Hive.box(_savedVideosBox);
    if (box.containsKey(video.id)) {
      await box.delete(video.id);
    } else {
      await box.put(video.id, video.toMap());
    }
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

  // ─────────── Theme ───────────

  /// The selected appearance: 'auto' | 'light' | 'dark' | 'black'
  /// ('black' = pitch-black AMOLED theme).
  ///
  /// Reads migrate from the legacy `theme_mode` key so existing users
  /// keep their choice after the update.
  String get themeOption {
    final stored = Hive.box(_settingsBox).get(_themeOptionKey);
    if (stored is String && themeOptions.contains(stored)) return stored;
    final legacy = Hive.box(_settingsBox).get(_themeModeKey);
    return switch (legacy) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'auto',
    };
  }

  Future<void> setThemeOption(String option) async {
    final safe = themeOptions.contains(option) ? option : 'auto';
    await Hive.box(_settingsBox).put(_themeOptionKey, safe);
    notifyListeners();
  }

  /// [ThemeMode] for [MaterialApp]: the pitch-black theme is a dark theme
  /// with black surfaces, so it maps to [ThemeMode.dark].
  ThemeMode get themeMode => switch (themeOption) {
        'light' => ThemeMode.light,
        'dark' || 'black' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// Whether the pitch-black (AMOLED) theme is active.
  bool get isPitchBlack => themeOption == 'black';

  /// Accent color (ARGB) used to seed the app theme. Defaults to the
  /// classic AdlessTube red.
  int get accentColor => Hive.box(_settingsBox)
      .get(_accentColorKey, defaultValue: 0xFFF44336) as int;

  Future<void> setAccentColor(int argb) async {
    await Hive.box(_settingsBox).put(_accentColorKey, argb);
    notifyListeners();
  }

  // ─────────── Video fit (fullscreen) ───────────

  /// How the video fills the player surface: 'fit' (whole video visible,
  /// letterboxed), 'crop' (zoom to fill, edges cropped) or 'stretch'
  /// (distorted to fill).
  String get videoFitMode {
    final stored = Hive.box(_settingsBox).get(_videoFitKey);
    return stored is String && videoFitModes.contains(stored) ? stored : 'fit';
  }

  Future<void> setVideoFitMode(String mode) async {
    final safe = videoFitModes.contains(mode) ? mode : 'fit';
    await Hive.box(_settingsBox).put(_videoFitKey, safe);
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

  /// Audio language the user last picked on a dubbed video — remembered so
  /// other videos with the same dub default to it (like the YouTube app).
  String get preferredAudioLocale => Hive.box(_settingsBox)
      .get(_preferredAudioLocaleKey, defaultValue: '') as String;

  Future<void> setPreferredAudioLocale(String locale) async {
    await Hive.box(_settingsBox).put(_preferredAudioLocaleKey, locale);
    notifyListeners();
  }

  // ─────────── Animations ───────────

  /// Whether UI animations (tab transitions, page slides, mini player)
  /// are enabled. Users can turn them off in Settings.
  bool get animationsEnabled => Hive.box(_settingsBox)
      .get(_animationsEnabledKey, defaultValue: true) as bool;

  Future<void> setAnimationsEnabled(bool enabled) async {
    await Hive.box(_settingsBox).put(_animationsEnabledKey, enabled);
    notifyListeners();
  }

  // ─────────── Backup: export / import ───────────

  /// Serializes every user-data box into a JSON-friendly map that can be
  /// written to a file and restored later with [importData].
  ///
  /// Downloads are intentionally excluded: the media files themselves
  /// live outside the app data and cannot travel inside a JSON backup.
  Future<Map<String, dynamic>> exportData() async {
    final boxes = <String, dynamic>{};
    for (final name in _backupBoxes) {
      final box = Hive.box(name);
      boxes[name] = {
        for (final key in box.keys) key.toString(): box.get(key),
      };
    }
    return {
      'app': 'AdlessTube',
      'backupVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'boxes': boxes,
    };
  }

  /// Validates and restores a backup produced by [exportData].
  /// Imported entries overwrite identical keys but never delete data
  /// that is not present in the backup, so importing into a used app
  /// merges instead of wiping.
  ///
  /// Returns the number of restored entries, or throws [FormatException]
  /// when the payload is not an AdlessTube backup.
  Future<int> importData(Map<String, dynamic> data) async {
    if (data['app'] != 'AdlessTube' || data['boxes'] is! Map) {
      throw const FormatException('Not an AdlessTube backup file.');
    }
    final boxes = Map<String, dynamic>.from(data['boxes'] as Map);
    var restored = 0;
    for (final name in _backupBoxes) {
      final raw = boxes[name];
      if (raw is! Map) continue;
      final box = Hive.box(name);
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value == null) continue;
        if (box.get(key) != value) {
          await box.put(key, value);
        }
        restored++;
      }
    }
    notifyListeners();
    return restored;
  }

  // ─────────── Feed impressions ───────────

  /// Videos the home feed recently displayed. Pull-to-refresh skips them so
  /// each refresh actually serves different content (like YouTube's "Not
  /// interested / seen" memory) instead of echoing the same list.
  Set<String> getShownFeedIds() {
    final raw = Hive.box(_settingsBox).get(_shownFeedKey);
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  Future<void> rememberShownFeedIds(Iterable<String> ids) async {
    final current = getShownFeedIds();
    current.addAll(ids);
    var list = current.toList();
    if (list.length > _shownFeedLimit) {
      list = list.sublist(list.length - _shownFeedLimit);
    }
    await Hive.box(_settingsBox).put(_shownFeedKey, list);
  }

  /// Wipes the impression memory — "Show me those again".
  Future<void> clearShownFeedIds() async {
    await Hive.box(_settingsBox).put(_shownFeedKey, <String>[]);
  }

  Map<String, dynamic>? getPlaybackState(String videoId) {
    final value = Hive.box(_playbackBox).get(videoId);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> savePlaybackState({
    required String videoId,
    required Duration position,
    required Duration duration,
    String? quality,
    String? format,
  }) {
    return Hive.box(_playbackBox).put(videoId, {
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'quality': quality,
      'format': format,
    });
  }

  /// Forces any pending playback-state write to disk — the app is about
  /// to be killed and the resume spot must survive.
  Future<void> flushPlayback() => Hive.box(_playbackBox).flush();

  // ─────────── Restorable audio session ───────────

  /// The audio-only session that was live when the app was last closed:
  /// {videoId, positionMs, durationMs}. Written continuously while a
  /// video plays audio-only, cleared when that session ends normally —
  /// the next app run brings it back as a paused mini player.
  Map<String, dynamic>? getLastAudioSession() {
    final value = Hive.box(_settingsBox).get(_lastAudioSessionKey);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> saveLastAudioSession({
    required String videoId,
    required Duration position,
    required Duration duration,
  }) {
    return Hive.box(_settingsBox).put(_lastAudioSessionKey, {
      'videoId': videoId,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
    });
  }

  Future<void> clearLastAudioSession() =>
      Hive.box(_settingsBox).delete(_lastAudioSessionKey);

  // ─────────── Search history ───────────

  /// Saves a search query (most recent first, capped at 30 entries).
  Future<void> addSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final box = Hive.box(_searchHistoryBox);
    await box.put(q, DateTime.now().millisecondsSinceEpoch);
    if (box.length > 30) {
      final entries = [
        for (final key in box.keys)
          MapEntry(key.toString(), (box.get(key) as int?) ?? 0),
      ]..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in entries.take(box.length - 30)) {
        await box.delete(entry.key);
      }
    }
    notifyListeners();
  }

  List<String> getSearchHistory() {
    final box = Hive.box(_searchHistoryBox);
    final entries = [
      for (final key in box.keys)
        MapEntry(key.toString(), (box.get(key) as int?) ?? 0),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) => entry.key).toList();
  }

  Future<void> removeSearchQuery(String query) async {
    await Hive.box(_searchHistoryBox).delete(query);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await Hive.box(_searchHistoryBox).clear();
    notifyListeners();
  }

  // ─────────── Subscriptions ───────────
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
