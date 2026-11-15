import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to persist and retrieve browsing history without emojis.
class HistoryService {
  static const String _keyHistory = 'user_browsing_history_v1';
  static const int _maxHistoryItems = 300;

  static HistoryService? _instance;
  static HistoryService get instance => _instance ??= HistoryService._();
  HistoryService._();

  Future<void> addHistory(Map<String, dynamic> post) async {
    final id = post['id']?.toString() ?? post['file_url']?.toString();
    if (id == null || id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHistory) ?? [];

    // Remove existing entry for the same post ID to bump it to front
    list.removeWhere((itemStr) {
      try {
        final map = json.decode(itemStr);
        final entryId = map['id']?.toString() ?? map['file_url']?.toString();
        return entryId == id;
      } catch (_) {
        return false;
      }
    });

    final siteValue = (post['site_id'] ?? post['site'] ?? '').toString();
    final record = <String, dynamic>{
      'id': post['id'],
      'site': siteValue,
      'site_id': siteValue,
      'preview_url': post['preview_url'] ?? post['sample_url'] ?? post['file_url'],
      'sample_url': post['sample_url'] ?? post['file_url'],
      'file_url': post['file_url'] ?? '',
      if (post['jpeg_url'] != null) 'jpeg_url': post['jpeg_url'],
      if (post['preview_width'] != null) 'preview_width': post['preview_width'],
      if (post['preview_height'] != null) 'preview_height': post['preview_height'],
      'width': post['width'],
      'height': post['height'],
      if (post['file_size'] != null) 'file_size': post['file_size'],
      if (post['file_ext'] != null) 'file_ext': post['file_ext'],
      'uploader': post['uploader'] ?? '',
      if (post['creator_id'] != null) 'creator_id': post['creator_id'],
      'author': post['author'] ?? '',
      if (post['artist_tags'] != null) 'artist_tags': post['artist_tags'],
      if (post['character_tags'] != null) 'character_tags': post['character_tags'],
      if (post['copyright_tags'] != null) 'copyright_tags': post['copyright_tags'],
      if (post['general_tags'] != null) 'general_tags': post['general_tags'],
      if (post['meta_tags'] != null) 'meta_tags': post['meta_tags'],
      if (post['score'] != null) 'score': post['score'],
      if (post['fav_count'] != null) 'fav_count': post['fav_count'],
      if (post['source'] != null) 'source': post['source'],
      if (post['post_url'] != null) 'post_url': post['post_url'],
      if (post['created_at'] != null) 'created_at': post['created_at'],
      if (post['has_children'] != null) 'has_children': post['has_children'],
      if (post['parent_id'] != null) 'parent_id': post['parent_id'],
      'rating': post['rating'] ?? '',
      'tags': post['tags'] ?? '',
      'viewed_at': DateTime.now().millisecondsSinceEpoch,
    };

    list.insert(0, json.encode(record));
    if (list.length > _maxHistoryItems) {
      list.removeRange(_maxHistoryItems, list.length);
    }

    await prefs.setStringList(_keyHistory, list);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHistory) ?? [];
    final result = <Map<String, dynamic>>[];
    for (final s in list) {
      try {
        result.add(Map<String, dynamic>.from(json.decode(s)));
      } catch (_) {}
    }
    return result;
  }

  Future<void> removeHistoryItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHistory) ?? [];
    list.removeWhere((itemStr) {
      try {
        final map = json.decode(itemStr);
        final entryId = map['id']?.toString() ?? map['file_url']?.toString();
        return entryId == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_keyHistory, list);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}
