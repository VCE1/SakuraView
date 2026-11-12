import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

class FavoritesManager {
  static const String _keyFavorites = 'favorites_posts_v2';
  static final Logger _logger = Logger('FavoritesManager');
  static List<Map<String, dynamic>>? _cachedFavorites;
  static DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  static Future<SharedPreferences> _getPrefs() async {
    return SharedPreferences.getInstance();
  }

  static void clearCache() {
    _cachedFavorites = null;
    _lastCacheTime = null;
  }

  static bool _isCacheValid() {
    if (_cachedFavorites == null || _lastCacheTime == null) return false;
    return DateTime.now().difference(_lastCacheTime!) < _cacheValidDuration;
  }

  static Future<void> addFavorite(Map<String, dynamic> postData) async {
    if (postData['id'] == null && postData['file_url'] == null) {
      _logger.warning('尝试添加缺少标识符的收藏项: $postData');
      return;
    }

    final prefs = await _getPrefs();
    List<String> favoritesJson = prefs.getStringList(_keyFavorites) ?? [];

    String identifier =
        (postData['id']?.toString() ?? postData['file_url']) as String;
    bool exists = false;
    for (String favJsonEntry in favoritesJson) {
      try {
        Map<String, dynamic> favMap = json.decode(favJsonEntry);
        String entryIdentifier =
            (favMap['id']?.toString() ?? favMap['file_url']) as String;
        if (entryIdentifier == identifier) {
          exists = true;
          break;
        }
      } catch (e) {
        _logger.severe('解码已存收藏项时出错: $e, item: $favJsonEntry');
      }
    }

    if (!exists) {
      try {
        Map<String, dynamic> postDataWithTimestamp = Map.from(postData);
        postDataWithTimestamp['favorited_at'] =
            DateTime.now().millisecondsSinceEpoch;

        favoritesJson.add(json.encode(postDataWithTimestamp));
        await prefs.setStringList(_keyFavorites, favoritesJson);
        clearCache();

        _logger.info('已添加收藏: $identifier');
      } catch (e) {
        _logger.severe('编码并添加收藏项时出错: $e, item: $postData');
        throw Exception('添加收藏失败: $e');
      }
    } else {
      _logger.info('项目已在收藏夹中: $identifier');
    }
  }

  static Future<void> removeFavorite(String identifier) async {
    final prefs = await _getPrefs();
    List<String> favoritesJson = prefs.getStringList(_keyFavorites) ?? [];
    int initialLength = favoritesJson.length;

    favoritesJson.removeWhere((favJson) {
      try {
        Map<String, dynamic> favMap = json.decode(favJson);
        String entryIdentifier =
            (favMap['id']?.toString() ?? favMap['file_url']) as String;
        return entryIdentifier == identifier;
      } catch (e) {
        _logger.severe('解码待移除收藏项时出错: $e, item: $favJson');
        return false;
      }
    });

    if (favoritesJson.length < initialLength) {
      await prefs.setStringList(_keyFavorites, favoritesJson);
      clearCache();

      _logger.info('已移除收藏: $identifier');
    } else {
      _logger.info('未在收藏夹中找到项目: $identifier');
      throw Exception('未找到要移除的收藏项');
    }
  }

  static Future<List<Map<String, dynamic>>> getFavorites(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid()) {
      return List.from(_cachedFavorites!);
    }

    final prefs = await _getPrefs();
    List<String> favoritesJson = prefs.getStringList(_keyFavorites) ?? [];
    List<Map<String, dynamic>> favoriteItems = [];

    for (String favJsonEntry in favoritesJson) {
      try {
        Map<String, dynamic> item =
            json.decode(favJsonEntry) as Map<String, dynamic>;
        favoriteItems.add(item);
      } catch (e) {
        _logger.severe('解码收藏项列表时出错: $e, item: $favJsonEntry');
      }
    }
    favoriteItems.sort((a, b) {
      int timeA = a['favorited_at'] ?? 0;
      int timeB = b['favorited_at'] ?? 0;
      return timeB.compareTo(timeA);
    });
    _cachedFavorites = favoriteItems;
    _lastCacheTime = DateTime.now();

    return favoriteItems;
  }

  static Future<bool> isFavorite(String identifier) async {
    if (_isCacheValid()) {
      return _cachedFavorites!.any((fav) {
        String entryIdentifier =
            (fav['id']?.toString() ?? fav['file_url']) as String;
        return entryIdentifier == identifier;
      });
    }
    List<Map<String, dynamic>> favorites = await getFavorites();
    return favorites.any((fav) {
      String entryIdentifier =
          (fav['id']?.toString() ?? fav['file_url']) as String;
      return entryIdentifier == identifier;
    });
  }

  static Future<int> getFavoritesCount() async {
    if (_isCacheValid()) {
      return _cachedFavorites!.length;
    }

    final favorites = await getFavorites();
    return favorites.length;
  }

  static Future<int> removeFavorites(List<String> identifiers) async {
    int removedCount = 0;

    for (String identifier in identifiers) {
      try {
        await removeFavorite(identifier);
        removedCount++;
      } catch (e) {
        _logger.warning('批量移除收藏失败: $identifier, 错误: $e');
      }
    }

    return removedCount;
  }

  static Future<void> clearAllFavorites() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyFavorites);
    clearCache();
    _logger.info('已清空所有收藏');
  }

  static Future<String> exportFavorites() async {
    final favorites = await getFavorites(forceRefresh: true);
    return json.encode(favorites);
  }

  static Future<int> importFavorites(String jsonData,
      {bool clearExisting = false}) async {
    try {
      List<dynamic> importData = json.decode(jsonData);

      if (clearExisting) {
        await clearAllFavorites();
      }

      int importedCount = 0;
      for (var item in importData) {
        if (item is Map<String, dynamic>) {
          try {
            await addFavorite(item);
            importedCount++;
          } catch (e) {
            _logger.warning('导入单个收藏项失败: $e');
          }
        }
      }

      return importedCount;
    } catch (e) {
      _logger.severe('导入收藏数据失败: $e');
      throw Exception('导入失败: $e');
    }
  }
}
