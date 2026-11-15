import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tag Blacklist Service
/// Manages blocked tags and provides rapid filtering for posts.
/// Pure clean implementation without emojis.
class BlacklistService extends ChangeNotifier {
  static const String _prefKey = 'user_tag_blacklist_v1';

  static BlacklistService? _instance;
  static BlacklistService get instance => _instance ??= BlacklistService._();

  final Set<String> _tags = <String>{};
  bool _initialized = false;

  BlacklistService._() {
    _loadFromPrefs();
  }

  /// Current blacklisted tags as a sorted unmodifiable list.
  List<String> get tags => List.unmodifiable(_tags.toList()..sort());

  /// Whether the blacklist is empty.
  bool get isEmpty => _tags.isEmpty;

  /// Number of blacklisted tags.
  int get count => _tags.length;

  /// Load blacklisted tags from SharedPreferences.
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey) ?? [];
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

  /// Ensure initialization has finished.
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await _loadFromPrefs();
    }
  }

  /// Whether a specific tag is currently blacklisted.
  bool isBlocked(String tag) {
    final clean = tag.trim().toLowerCase();
    return clean.isNotEmpty && _tags.contains(clean);
  }

  /// Add a tag to the blacklist.
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

  /// Remove a tag from the blacklist.
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

  /// Clear all tags from the blacklist.
  Future<void> clearAll() async {
    if (_tags.isEmpty) return;
    _tags.clear();
    await _saveToPrefs();
    notifyListeners();
  }

  /// Save current tags to SharedPreferences.
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _tags.toList());
    } catch (_) {}
  }

  /// Check whether a given post contains any blacklisted tag.
  bool isPostBlocked(Map<String, dynamic> post) {
    if (_tags.isEmpty) return false;

    final tagSources = <String?>[
      post['tags'] as String?,
      post['tag_string'] as String?,
      post['tag_string_general'] as String?,
      post['tag_string_character'] as String?,
      post['tag_string_artist'] as String?,
      post['tag_string_copyright'] as String?,
    ];

    for (final src in tagSources) {
      if (src == null || src.isEmpty) continue;
      final tokens = src.split(RegExp(r'[\s,]+'));
      for (final token in tokens) {
        final lower = token.trim().toLowerCase();
        if (lower.isNotEmpty && _tags.any((blocked) => lower == blocked || lower.contains(blocked))) {
          return true;
        }
      }
    }

    return false;
  }
}
