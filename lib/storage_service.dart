import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';

class StorageService extends ChangeNotifier {
  static const _historyBox = 'history';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_historyBox);
  }

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
}
