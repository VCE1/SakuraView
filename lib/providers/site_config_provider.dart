import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/api/api_client_factory.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

class SiteConfigProvider extends ChangeNotifier {
  static const String _key = 'site_config';

  SiteConfig _config =
      const SiteConfig(site: ImageSite.yandere, safeMode: true);
  ImageApiClient? _client;

  SiteConfig get config => _config;
  ImageApiClient get apiClient {
    _client ??= ApiClientFactory.createClient(_config);
    return _client!;
  }

  SiteAccountCredentials credentialsFor(ImageSite site) =>
      _config.credentialsFor(site);

  SiteConfigProvider() {
    _loadConfig();
  }

  void _syncImageHeaderRegistry() {
    for (final site in ImageSite.values) {
      final creds = _config.credentialsFor(site);
      SiteImageHeaderRegistry.setSiteAuthHeaders(
        domainKeyword: site.domainKeyword,
        cookies: creds.cookies,
        userAgent: creds.userAgent,
      );
    }
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = SiteConfig.fromJson(json);
        _syncImageHeaderRegistry();
        _client = ApiClientFactory.createClient(_config);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load site config: $e');
    }
  }

  Future<void> setSite(ImageSite site) async {
    if (_config.site == site) return;
    final creds = _config.credentialsFor(site);
    _config = _config.copyWith(
      site: site,
      username: creds.username,
      apiKey: creds.apiKey,
      cookies: creds.cookies,
      userAgent: creds.userAgent,
    );
    _syncImageHeaderRegistry();
    _client = ApiClientFactory.createClient(_config);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setSafeMode(bool safeMode) async {
    if (_config.safeMode == safeMode) return;
    _config = _config.copyWith(safeMode: safeMode);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> updateSiteCredentials(
    ImageSite site, {
    String? username,
    String? apiKey,
    String? cookies,
    String? userAgent,
  }) async {
    final current = _config.credentialsFor(site);
    final updated = current.copyWith(
      username: username,
      apiKey: apiKey,
      cookies: cookies,
      userAgent: userAgent,
    );
    final nextAccounts =
        Map<ImageSite, SiteAccountCredentials>.from(_config.accounts);
    nextAccounts[site] = updated;

    _config = _config.copyWith(
      accounts: nextAccounts,
      username: site == _config.site ? updated.username : _config.username,
      apiKey: site == _config.site ? updated.apiKey : _config.apiKey,
      cookies: site == _config.site ? updated.cookies : _config.cookies,
      userAgent: site == _config.site ? updated.userAgent : _config.userAgent,
    );
    _syncImageHeaderRegistry();
    _client = ApiClientFactory.createClient(_config);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> clearSiteCredentials(ImageSite site) async {
    await updateSiteCredentials(
      site,
      username: '',
      apiKey: '',
      cookies: '',
      userAgent: '',
    );
  }

  Future<void> setApiKey(String apiKey) async {
    await updateSiteCredentials(_config.site, apiKey: apiKey);
  }

  Future<void> setUsername(String username) async {
    await updateSiteCredentials(_config.site, username: username);
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('Failed to save site config: $e');
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
