import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 快速搜索预设条目（参考 JHenTai QuickSearch 数据结构）。
class QuickSearchEntry {
  final String id;
  final String label;
  final String query;
  final String uploader;
  final String artist;
  final String? sort;

  const QuickSearchEntry({
    required this.id,
    required this.label,
    required this.query,
    this.uploader = '',
    this.artist = '',
    this.sort,
  });

  String get signature =>
      '${query.trim().toLowerCase()}|${uploader.trim().toLowerCase()}|${artist.trim().toLowerCase()}|${(sort ?? '').trim().toLowerCase()}';

  String get subtitle {
    final parts = <String>[
      if (query.trim().isNotEmpty) query.trim(),
      if (artist.trim().isNotEmpty) '画师:${artist.trim()}',
      if (uploader.trim().isNotEmpty) '上传:${uploader.trim()}',
      if (sort != null && sort!.trim().isNotEmpty) '排序:${sort!.trim()}',
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'query': query,
        'uploader': uploader,
        'artist': artist,
        if (sort != null && sort!.isNotEmpty) 'sort': sort,
      };

  factory QuickSearchEntry.fromJson(Map<String, dynamic> json) {
    final q = json['query']?.toString() ?? '';
    final u = json['uploader']?.toString() ?? '';
    final a = json['artist']?.toString() ?? '';
    final s = json['sort']?.toString();
    final rawLabel = json['label']?.toString().trim() ?? '';
    final fallbackLabel = q.trim().isNotEmpty
        ? q.trim()
        : (a.trim().isNotEmpty ? '画师:${a.trim()}' : '上传:${u.trim()}');
    return QuickSearchEntry(
      id: json['id']?.toString() ??
          'qs_${DateTime.now().microsecondsSinceEpoch}',
      label: rawLabel.isNotEmpty ? rawLabel : fallbackLabel,
      query: q,
      uploader: u,
      artist: a,
      sort: (s != null && s.trim().isNotEmpty) ? s.trim() : null,
    );
  }
}

class RecentTagsNotifier extends ChangeNotifier {
  static const String _key = 'recentTags';
  static const String _quickKey = 'quickSearchesV1';
  static const int _maxTags = 20;
  static const int _maxQuickSearches = 30;

  List<String> _tags = [];
  List<QuickSearchEntry> _quickSearches = [];

  List<String> get tags => List.unmodifiable(_tags);
  List<QuickSearchEntry> get quickSearches => List.unmodifiable(_quickSearches);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _tags = prefs.getStringList(_key) ?? [];
    final rawQuick = prefs.getString(_quickKey);
    if (rawQuick != null && rawQuick.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQuick);
        if (decoded is List) {
          _quickSearches = decoded
              .whereType<Map<String, dynamic>>()
              .map(QuickSearchEntry.fromJson)
              .where((e) =>
                  e.query.trim().isNotEmpty ||
                  e.uploader.trim().isNotEmpty ||
                  e.artist.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
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

    await _saveTags();
    notifyListeners();
  }

  Future<void> removeTag(String tag) async {
    _tags.remove(tag);
    await _saveTags();
    notifyListeners();
  }

  Future<void> clear() async {
    _tags.clear();
    await _saveTags();
    notifyListeners();
  }

  bool hasQuickSearch({
    required String query,
    String uploader = '',
    String artist = '',
    String? sort,
  }) {
    final target = QuickSearchEntry(
      id: '',
      label: '',
      query: query,
      uploader: uploader,
      artist: artist,
      sort: sort,
    ).signature;
    return _quickSearches.any((e) => e.signature == target);
  }

  Future<void> addQuickSearch({
    required String label,
    required String query,
    String uploader = '',
    String artist = '',
    String? sort,
  }) async {
    final entry = QuickSearchEntry(
      id: 'qs_${DateTime.now().microsecondsSinceEpoch}',
      label: label.trim().isNotEmpty
          ? label.trim()
          : (query.trim().isNotEmpty ? query.trim() : '自定义搜索'),
      query: query.trim(),
      uploader: uploader.trim(),
      artist: artist.trim(),
      sort: (sort != null && sort.trim().isNotEmpty) ? sort.trim() : null,
    );
    if (entry.query.isEmpty &&
        entry.uploader.isEmpty &&
        entry.artist.isEmpty) {
      return;
    }

    _quickSearches.removeWhere((e) => e.signature == entry.signature);
    _quickSearches.insert(0, entry);
    if (_quickSearches.length > _maxQuickSearches) {
      _quickSearches = _quickSearches.sublist(0, _maxQuickSearches);
    }
    await _saveQuickSearches();
    notifyListeners();
  }

  Future<bool> toggleQuickSearch({
    required String query,
    String uploader = '',
    String artist = '',
    String? sort,
    String? label,
  }) async {
    final target = QuickSearchEntry(
      id: '',
      label: '',
      query: query,
      uploader: uploader,
      artist: artist,
      sort: sort,
    ).signature;
    final idx = _quickSearches.indexWhere((e) => e.signature == target);
    if (idx >= 0) {
      _quickSearches.removeAt(idx);
      await _saveQuickSearches();
      notifyListeners();
      return false;
    }
    await addQuickSearch(
      label: label ?? (query.trim().isNotEmpty ? query.trim() : '自定义筛选'),
      query: query,
      uploader: uploader,
      artist: artist,
      sort: sort,
    );
    return true;
  }

  Future<void> removeQuickSearch(String id) async {
    _quickSearches.removeWhere((e) => e.id == id);
    await _saveQuickSearches();
    notifyListeners();
  }

  Future<void> clearQuickSearches() async {
    _quickSearches.clear();
    await _saveQuickSearches();
    notifyListeners();
  }

  Future<void> _saveTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _tags);
  }

  Future<void> _saveQuickSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _quickKey,
      jsonEncode(_quickSearches.map((e) => e.toJson()).toList()),
    );
  }
}
