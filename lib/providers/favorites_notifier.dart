import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/utils/favorites.dart'; // 鍋囪浣犵殑 FavoritesManager 鍦ㄨ繖閲?

class FavoritesNotifier extends ChangeNotifier {
  List<Map<String, dynamic>> _favoriteItems = [];
  final Set<String> _favoriteIdentifiers = {};

  FavoritesNotifier() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesManager.getFavorites();
    _favoriteItems = favorites;
    _favoriteIdentifiers.clear(); // 鍏堟竻绌猴紝鍐嶉噸鏂板～鍏?
    for (var item in favorites) {
      _favoriteIdentifiers
          .add((item['id']?.toString() ?? item['file_url']) as String);
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get favoriteItems => _favoriteItems;
  bool isFavorite(String identifier) {
    return _favoriteIdentifiers.contains(identifier);
  }

  Future<void> toggleFavorite(Map<String, dynamic> postData) async {
    final String identifier =
        (postData['id']?.toString() ?? postData['file_url']) as String;
    if (_favoriteIdentifiers.contains(identifier)) {
      await FavoritesManager.removeFavorite(identifier);
      _favoriteItems.removeWhere(
          (item) => (item['id']?.toString() ?? item['file_url']) == identifier);
      _favoriteIdentifiers.remove(identifier);
    } else {
      await FavoritesManager.addFavorite(postData);
      await _loadFavorites();
    }
    notifyListeners(); // 閫氱煡鎵€鏈夌洃鍚€呯姸鎬佸凡鏀瑰彉
  }
}

