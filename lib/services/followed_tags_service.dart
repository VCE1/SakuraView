import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 特别关注标签服务：持久化用户重点关注的画师、角色或题材标签，支持快速检索与视觉标记。
class FollowedTagsService extends ChangeNotifier {
  static const String _prefKey = 'user_followed_tags_v1';

  static FollowedTagsService? _instance;
  static FollowedTagsService get instance => _instance ??= FollowedTagsService._();

  final Set<String> _tags = <String>{};
  bool _initialized = false;

  FollowedTagsService._() {
    _loadFromPrefs();
  }

  /// 当前已关注的标签列表（按字典序升序排列）。
  List<String> get tags => List.unmodifiable(_tags.toList()..sort());

  bool get isEmpty => _tags.isEmpty;

  int get count => _tags.length;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey) ?? const <String>[];
      _tags.clear();
      for (final t in list) {
        final clean = t.trim().toLowerCase();
        if (clean.isNotEmpty) {
          _tags.add(clean);
        }
      }
      _initialized = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await _loadFromPrefs();
    }
  }

  bool isFollowed(String tag) {
    final clean = tag.trim().toLowerCase();
    return clean.isNotEmpty && _tags.contains(clean);
  }

  Future<bool> addTag(String tag) async {
    final clean = tag.trim().toLowerCase();
    if (clean.isEmpty || _tags.contains(clean)) {
      return false;
    }
    _tags.add(clean);
    await _saveToPrefs();
    notifyListeners();
    return true;
  }

  Future<bool> removeTag(String tag) async {
    final clean = tag.trim().toLowerCase();
    if (!_tags.contains(clean)) {
      return false;
    }
    _tags.remove(clean);
    await _saveToPrefs();
    notifyListeners();
    return true;
  }

  Future<bool> toggleTag(String tag) async {
    if (isFollowed(tag)) {
      await removeTag(tag);
      return false;
    }
    await addTag(tag);
    return true;
  }

  Future<void> clearAll() async {
    if (_tags.isEmpty) return;
    _tags.clear();
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _tags.toList());
    } catch (_) {}
  }
}
