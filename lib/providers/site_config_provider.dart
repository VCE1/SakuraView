import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/api/api_client_factory.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';

class SiteConfigProvider extends ChangeNotifier {
  static const String _key = 'site_config';

  SiteConfig _config = const SiteConfig(site: ImageSite.yandere, safeMode: true);
  ImageApiClient? _client;

  SiteConfig get config => _config;
  ImageApiClient get apiClient {
    _client ??= ApiClientFactory.createClient(_config);
    return _client!;
  }

  SiteConfigProvider() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = SiteConfig.fromJson(json);
        _client = ApiClientFactory.createClient(_config);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load site config: $e');
    }
  }

  Future<void> setSite(ImageSite site) async {
    if (_config.site == site) return;
    _config = _config.copyWith(site: site);
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

  Future<void> setApiKey(String apiKey) async {
    _config = _config.copyWith(apiKey: apiKey);
    _client = ApiClientFactory.createClient(_config);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setUsername(String username) async {
    _config = _config.copyWith(username: username);
    _client = ApiClientFactory.createClient(_config);
    notifyListeners();
    await _saveConfig();
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
