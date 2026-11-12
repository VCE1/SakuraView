import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/utils/favorites.dart';

class FavoritesNotifier extends ChangeNotifier {
  List<Map<String, dynamic>> _favoriteItems = [];
  final Set<String> _favoriteIdentifiers = {};

  final List<Map<String, dynamic>> _cloudItems = [];
  bool _isCloudLoading = false;
  String? _cloudError;
  int _cloudPage = 1;
  bool _hasMoreCloud = true;

  FavoritesNotifier() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesManager.getFavorites(forceRefresh: true);
    _favoriteItems = favorites;
    _favoriteIdentifiers.clear();
    for (var item in favorites) {
      final id = (item['id']?.toString() ?? item['file_url']) as String?;
      if (id != null) {
        _favoriteIdentifiers.add(id);
      }
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get favoriteItems => _favoriteItems;
  List<Map<String, dynamic>> get cloudItems => _cloudItems;
  bool get isCloudLoading => _isCloudLoading;
  String? get cloudError => _cloudError;
  bool get hasMoreCloud => _hasMoreCloud;

  bool isFavorite(String identifier) {
    return _favoriteIdentifiers.contains(identifier);
  }

  Future<void> toggleFavorite(
    Map<String, dynamic> postData, {
    String? siteName,
  }) async {
    final String identifier =
        (postData['id']?.toString() ?? postData['file_url']) as String;
    if (_favoriteIdentifiers.contains(identifier)) {
      await FavoritesManager.removeFavorite(identifier);
      _favoriteItems.removeWhere(
          (item) => (item['id']?.toString() ?? item['file_url']) == identifier);
      _favoriteIdentifiers.remove(identifier);
    } else {
      final copy = Map<String, dynamic>.from(postData);
      if (siteName != null && (copy['site'] == null || copy['site'] == '')) {
        copy['site'] = siteName;
      }
      await FavoritesManager.addFavorite(copy);
      await _loadFavorites();
    }
    notifyListeners();
  }

  Future<void> fetchCloudFavorites(
    SiteConfigProvider siteProvider, {
    bool clear = false,
  }) async {
    if (clear) {
      _cloudItems.clear();
      _cloudPage = 1;
      _hasMoreCloud = true;
      _cloudError = null;
      notifyListeners();
    }
    if (_isCloudLoading || !_hasMoreCloud) return;

    _isCloudLoading = true;
    _cloudError = null;
    notifyListeners();

    try {
      final site = siteProvider.config.site;
      final posts = await siteProvider.apiClient.fetchCloudFavorites(
        page: _cloudPage,
        limit: 40,
        safeMode: siteProvider.config.safeMode,
      );
      if (posts.isEmpty) {
        _hasMoreCloud = false;
      } else {
        for (final p in posts) {
          final map = p.toApiMap();
          map['site'] = site.name;
          _cloudItems.add(map);
        }
        _cloudPage++;
      }
    } catch (e) {
      _cloudError = e.toString().replaceFirst('ApiException: ', '');
      _hasMoreCloud = false;
    } finally {
      _isCloudLoading = false;
      notifyListeners();
    }
  }

  Future<int> syncCloudToLocal() async {
    int added = 0;
    for (final item in _cloudItems) {
      final id = (item['id']?.toString() ?? item['file_url']) as String?;
      if (id != null && !_favoriteIdentifiers.contains(id)) {
        await FavoritesManager.addFavorite(item);
        added++;
      }
    }
    if (added > 0) {
      await _loadFavorites();
    }
    return added;
  }

  Future<void> clearAllLocalFavorites() async {
    await FavoritesManager.clearAllFavorites();
    await _loadFavorites();
  }
}
