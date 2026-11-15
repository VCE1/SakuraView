import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/utils/favorites.dart';

class FavoritesNotifier extends ChangeNotifier {
  List<Map<String, dynamic>> _favoriteItems = [];
  final Set<String> _favoriteIdentifiers = {};

  final List<Map<String, dynamic>> _cloudItems = [];
  String _cloudSiteId = '';
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
  String get cloudSiteId => _cloudSiteId;
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
    await _toggleLocalFavorite(postData, siteName: siteName);
  }

  Future<bool> _toggleLocalFavorite(
    Map<String, dynamic> postData, {
    String? siteName,
  }) async {
    final String identifier =
        (postData['id']?.toString() ?? postData['file_url']) as String;
    final bool nowFav;
    if (_favoriteIdentifiers.contains(identifier)) {
      await FavoritesManager.removeFavorite(identifier);
      _favoriteItems.removeWhere(
          (item) => (item['id']?.toString() ?? item['file_url']) == identifier);
      _favoriteIdentifiers.remove(identifier);
      nowFav = false;
    } else {
      final copy = Map<String, dynamic>.from(postData);
      if (siteName != null && (copy['site'] == null || copy['site'] == '')) {
        copy['site'] = siteName;
      }
      await FavoritesManager.addFavorite(copy);
      await _loadFavorites();
      nowFav = true;
    }
    notifyListeners();
    return nowFav;
  }

  /// 切换本地收藏，并在适配器支持云端收藏且已登录时同步到站点云端。
  Future<({bool isFavorite, bool cloudSynced, String? cloudMessage})>
      toggleFavoriteWithCloudSync(
    Map<String, dynamic> postData, {
    String? siteName,
    ImageSourceAdapter? adapter,
  }) async {
    final nowFav = await _toggleLocalFavorite(postData, siteName: siteName);
    if (adapter == null || !adapter.descriptor.capabilities.supportsCloudFavorites) {
      return (isFavorite: nowFav, cloudSynced: false, cloudMessage: null);
    }

    final postId = postData['id']?.toString().trim() ?? '';
    if (postId.isEmpty) {
      return (isFavorite: nowFav, cloudSynced: false, cloudMessage: null);
    }

    if (!adapter.hasWriteCredentials) {
      return (
        isFavorite: nowFav,
        cloudSynced: false,
        cloudMessage: null,
      );
    }

    try {
      final ok = nowFav
          ? await adapter.addCloudFavorite(postId)
          : await adapter.removeCloudFavorite(postId);
      if (ok &&
          (_cloudSiteId.isEmpty || _cloudSiteId == adapter.descriptor.id)) {
        if (nowFav) {
          final exists =
              _cloudItems.any((e) => e['id']?.toString() == postId);
          if (!exists) {
            final copy = Map<String, dynamic>.from(postData);
            copy['site'] = adapter.descriptor.id;
            copy['site_id'] = adapter.descriptor.id;
            _cloudItems.insert(0, copy);
          }
        } else {
          _cloudItems.removeWhere((e) => e['id']?.toString() == postId);
        }
        notifyListeners();
      }
      return (
        isFavorite: nowFav,
        cloudSynced: ok,
        cloudMessage: null,
      );
    } catch (e) {
      final reason = e.toString().replaceFirst('ApiException: ', '');
      return (
        isFavorite: nowFav,
        cloudSynced: false,
        cloudMessage: '本地收藏已更新，云端同步失败：$reason',
      );
    }
  }

  Future<void> fetchCloudFavorites(
    SiteConfigProvider siteProvider, {
    bool clear = false,
  }) async {
    final siteId = siteProvider.currentSourceId;
    final siteChanged = _cloudSiteId.isNotEmpty && _cloudSiteId != siteId;
    if (clear || siteChanged) {
      _cloudItems.clear();
      _cloudSiteId = siteId;
      _cloudPage = 1;
      _hasMoreCloud = true;
      _cloudError = null;
      notifyListeners();
    }
    if (_cloudSiteId.isEmpty) {
      _cloudSiteId = siteId;
    }
    if (_isCloudLoading || !_hasMoreCloud) return;

    _isCloudLoading = true;
    _cloudError = null;
    notifyListeners();

    try {
      final adapter = siteProvider.apiClient;
      if (adapter is DanbooruSourceAdapter) {
        final creds = siteProvider.credentialsForSource(siteId);
        if (creds.username.trim().isEmpty || creds.username.contains('@')) {
          final profile = await adapter.resolveAuthenticatedProfile();
          if (profile != null && profile.name.isNotEmpty) {
            await siteProvider.updateCredentialsById(
              siteId,
              username: profile.name,
              userId: profile.id.isNotEmpty ? profile.id : null,
            );
          }
        }
      }

      final posts = await siteProvider.apiClient.fetchCloudFavorites(
        page: _cloudPage,
        limit: 40,
        safeMode: siteProvider.config.safeMode,
        ratingFilter: siteProvider.ratingFilter,
      );
      if (posts.isEmpty) {
        _hasMoreCloud = false;
      } else {
        final existingIds =
            _cloudItems.map((e) => e['id']?.toString() ?? '').toSet();
        for (final p in posts) {
          final idStr = p.id.toString();
          if (existingIds.contains(idStr)) continue;
          existingIds.add(idStr);
          final map = p.toApiMap(siteName: siteId);
          map['site'] = siteId;
          map['site_id'] = siteId;
          _cloudItems.add(map);
        }
        _cloudPage++;
        if (posts.length < 40) {
          _hasMoreCloud = false;
        }
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
