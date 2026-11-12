import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentTagsNotifier extends ChangeNotifier {
  static const String _key = 'recentTags';
  static const int _maxTags = 20;

  List<String> _tags = [];
  List<String> get tags => List.unmodifiable(_tags);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _tags = raw;
    notifyListeners();
  }

  Future<void> addTag(String tag) async {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isEmpty) return;

    _tags.remove(normalized);
    _tags.insert(0, normalized);
    if (_tags.length > _maxTags) {
      _tags = _tags.sublist(0, _maxTags);
    }

    await _save();
    notifyListeners();
  }

  Future<void> removeTag(String tag) async {
    _tags.remove(tag);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _tags.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _tags);
  }
}
