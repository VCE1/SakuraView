import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/source_adapter_factory.dart';
import 'package:vce1_sakuraview/core/sources/source_config_parser.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

/// 全局图源注册、启用隔离、认证凭据与健康状态管理中心。
///
/// 核心原则（参考 Venera 扩展隔离架构）：
/// - 内置新图源（Konachan / Gelbooru / Rule34 / Sakugabooru / E-Shuushuu）
///   与第三方 JSON 导入图源默认均为禁用状态（`isEnabled: false`）。
/// - 首页图源切换器、抽屉面板及默认搜索仅暴露 `enabledSources` 中的启用图源。
/// - 单个图源的配置缺失、鉴权失败或网络故障均以独立 [SourceHealthState] 隔离。
class SiteConfigProvider extends ChangeNotifier {
  static const String _legacyKey = 'site_config';
  static const String _registryKey = 'source_registry_v2';

  String _currentSourceId = 'yandere';
  RatingFilterMode _ratingFilter = RatingFilterMode.safe;
  final Map<String, bool> _enabledOverrides = {};
  final List<SourceDescriptor> _customSources = [];
  final Map<String, SourceAccountCredentials> _accounts = {};
  final Map<String, SourceHealthState> _healthStates = {};

  ImageApiClient? _client;

  SiteConfigProvider() {
    _syncImageHeaderRegistry();
    _loadConfig();
  }

  /// 所有已注册图源（内置 9 个 + 用户导入/自定义扩展）。
  List<SourceDescriptor> get allSources {
    final result = <SourceDescriptor>[];
    for (final builtIn in BuiltInSources.catalog) {
      final enabled = _enabledOverrides[builtIn.id] ?? builtIn.defaultEnabled;
      result.add(builtIn.copyWith(isEnabled: enabled));
    }
    for (final custom in _customSources) {
      final enabled = _enabledOverrides[custom.id] ?? custom.defaultEnabled;
      result.add(custom.copyWith(isEnabled: enabled));
    }
    return result;
  }

  /// 仅返回当前明确启用的图源（未启用图源绝不自动加入首页切换器或搜索源）。
  List<SourceDescriptor> get enabledSources {
    final list = allSources.where((s) => s.isEnabled).toList();
    if (list.isEmpty) {
      final fallback = BuiltInSources.findById('yandere') ??
          BuiltInSources.catalog.first;
      return [fallback.copyWith(isEnabled: true)];
    }
    return list;
  }

  String get currentSourceId {
    final active = findSourceById(_currentSourceId);
    if (active != null && active.isEnabled) {
      return active.id;
    }
    return enabledSources.first.id;
  }

  SourceDescriptor get currentSource {
    final id = currentSourceId;
    return findSourceById(id) ?? enabledSources.first;
  }

  RatingFilterMode get ratingFilter => _ratingFilter;

  bool get safeMode => _ratingFilter.isSafe;

  /// 向后兼容旧代码对 [SiteConfig] 的访问（例如 safeMode 读取与切换）。
  SiteConfig get config {
    final legacySite = currentSource.legacyImageSite ?? ImageSite.yandere;
    final legacyCreds = credentialsForSource(currentSourceId).toLegacy();
    final legacyAccounts = <ImageSite, SiteAccountCredentials>{};
    for (final s in ImageSite.values) {
      legacyAccounts[s] = credentialsForSource(s.name).toLegacy();
    }
    return SiteConfig(
      site: legacySite,
      apiKey: legacyCreds.apiKey,
      username: legacyCreds.username,
      cookies: legacyCreds.cookies,
      userAgent: legacyCreds.userAgent,
      safeMode: safeMode,
      accounts: legacyAccounts,
    );
  }

  ImageSite get currentSite =>
      currentSource.legacyImageSite ?? ImageSite.yandere;

  ImageApiClient get apiClient {
    _client ??= _buildClient(currentSourceId);
    return _client!;
  }

  SourceDescriptor? findSourceById(String id) {
    final target = id.trim().toLowerCase();
    for (final s in allSources) {
      if (s.id == target) return s;
    }
    return null;
  }

  /// 为指定图源（包括暂未在首页启用的历史/收藏来源）构造独立的隔离适配器。
  ImageSourceAdapter adapterFor(String sourceId) => _buildClient(sourceId);

  ImageSourceAdapter _buildClient(String sourceId) {
    final descriptor = findSourceById(sourceId) ?? currentSource;
    final creds = credentialsForSource(descriptor.id);
    return SourceAdapterFactory.create(
      descriptor: descriptor,
      credentials: creds,
    );
  }

  SourceAccountCredentials credentialsForSource(String sourceId) =>
      _accounts[sourceId.trim().toLowerCase()] ??
      const SourceAccountCredentials();

  SiteAccountCredentials credentialsFor(ImageSite site) =>
      credentialsForSource(site.name).toLegacy();

  SourceHealthState? healthStateFor(String sourceId) =>
      _healthStates[sourceId.trim().toLowerCase()];

  void _syncImageHeaderRegistry() {
    for (final source in allSources) {
      final creds = credentialsForSource(source.id);
      final keywords = source.domainKeywords.isNotEmpty
          ? source.domainKeywords
          : [Uri.tryParse(source.baseUrl)?.host.toLowerCase() ?? '']
              .where((e) => e.isNotEmpty)
              .toList();
      for (final kw in keywords) {
        SiteImageHeaderRegistry.setSiteAuthHeaders(
          domainKeyword: kw,
          cookies: creds.cookies,
          userAgent: creds.userAgent,
          referer: source.effectiveReferer,
        );
      }
    }
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 优先读取新版多图源持久化结构
      final v2Json = prefs.getString(_registryKey);
      if (v2Json != null && v2Json.isNotEmpty) {
        final decoded = jsonDecode(v2Json) as Map<String, dynamic>;
        final rawRating = decoded['ratingFilter'] as String?;
        if (rawRating != null && rawRating.isNotEmpty) {
          _ratingFilter = RatingFilterMode.fromName(rawRating);
        } else {
          final legacySafe = decoded['safeMode'] as bool? ?? true;
          _ratingFilter =
              legacySafe ? RatingFilterMode.safe : RatingFilterMode.all;
        }
        _currentSourceId =
            (decoded['currentSourceId'] as String? ?? 'yandere').toLowerCase();

        final rawEnabled = decoded['enabledOverrides'];
        if (rawEnabled is Map) {
          _enabledOverrides
            ..clear()
            ..addEntries(
              rawEnabled.entries
                  .where((e) => e.key.toString().toLowerCase() != 'tbib')
                  .map(
                    (e) => MapEntry(
                      e.key.toString().toLowerCase(),
                      e.value == true,
                    ),
                  ),
            );
        }

        final rawCustom = decoded['customSources'];
        if (rawCustom is List) {
          _customSources.clear();
          for (final item in rawCustom) {
            if (item is Map<String, dynamic>) {
              try {
                final parsed = SourceDescriptor.fromJson(item, isBuiltIn: false);
                if (parsed.id.isNotEmpty &&
                    BuiltInSources.findById(parsed.id) == null) {
                  _customSources.add(parsed);
                }
              } catch (_) {}
            }
          }
        }

        final rawAccounts = decoded['accounts'];
        if (rawAccounts is Map) {
          _accounts.clear();
          for (final entry in rawAccounts.entries) {
            if (entry.value is Map<String, dynamic>) {
              _accounts[entry.key.toString().toLowerCase()] =
                  SourceAccountCredentials.fromJson(
                entry.value as Map<String, dynamic>,
              );
            }
          }
        }
      } else {
        // 2. 平滑迁移旧版 `site_config`
        final legacyStr = prefs.getString(_legacyKey);
        if (legacyStr != null && legacyStr.isNotEmpty) {
          final legacy =
              SiteConfig.fromJson(jsonDecode(legacyStr) as Map<String, dynamic>);
          _ratingFilter =
              legacy.safeMode ? RatingFilterMode.safe : RatingFilterMode.all;
          _currentSourceId = legacy.site.name;
          for (final s in ImageSite.values) {
            final c = legacy.credentialsFor(s);
            if (c.isConfigured || c.userAgent.isNotEmpty) {
              _accounts[s.name] = SourceAccountCredentials.fromLegacy(c);
            }
          }
        }
      }

      // 确保当前选中源属于已启用列表（避免升级或导入后落到禁用源上）
      if (findSourceById(_currentSourceId)?.isEnabled != true) {
        _currentSourceId = enabledSources.first.id;
      }

      _syncImageHeaderRegistry();
      _client?.close();
      _client = _buildClient(currentSourceId);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load source config: $e');
    }
  }

  Future<void> setSourceById(String sourceId) async {
    final target = findSourceById(sourceId);
    if (target == null || !target.isEnabled) return;
    if (_currentSourceId == target.id) return;
    _currentSourceId = target.id;
    _syncImageHeaderRegistry();
    _client?.close();
    _client = _buildClient(target.id);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setSite(ImageSite site) async {
    await setSourceById(site.name);
  }

  Future<void> setRatingFilter(RatingFilterMode mode) async {
    if (_ratingFilter == mode) return;
    _ratingFilter = mode;
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setSafeMode(bool safeMode) async {
    await setRatingFilter(
      safeMode ? RatingFilterMode.safe : RatingFilterMode.all,
    );
  }

  /// 启用或禁用单个图源；至少保留 1 个启用图源，防止首页无源可用。
  Future<bool> setSourceEnabled(String sourceId, bool enabled) async {
    final target = findSourceById(sourceId);
    if (target == null) return false;
    final cleanId = target.id;

    if (!enabled) {
      final otherEnabledCount =
          enabledSources.where((s) => s.id != cleanId).length;
      if (otherEnabledCount == 0) {
        return false;
      }
    }

    _enabledOverrides[cleanId] = enabled;
    if (!enabled && _currentSourceId == cleanId) {
      _currentSourceId = enabledSources.first.id;
      _client?.close();
      _client = _buildClient(_currentSourceId);
    } else if (_currentSourceId == cleanId) {
      _client?.close();
      _client = _buildClient(cleanId);
    }

    _syncImageHeaderRegistry();
    notifyListeners();
    await _saveConfig();
    return true;
  }

  /// 导入 Venera 风格单个 JSON 或清单列表（所有新导入图源默认处于禁用状态）。
  Future<int> importSourcesJson(String rawJson) async {
    final imported = SourceConfigParser.parseImportPayload(rawJson);
    int count = 0;
    for (final src in imported) {
      if (BuiltInSources.findById(src.id) != null) {
        throw FormatException('图源 ID "${src.id}" 与内置图源冲突，请更换 ID');
      }
      _customSources.removeWhere((e) => e.id == src.id);
      _customSources.add(src.copyWith(isBuiltIn: false, isEnabled: false));
      _enabledOverrides[src.id] = false;
      count++;
    }
    _syncImageHeaderRegistry();
    notifyListeners();
    await _saveConfig();
    return count;
  }

  /// 手动新增或更新自定义 JSON 图源（默认禁用，需用户显式开启）。
  Future<void> addOrUpdateCustomSource(SourceDescriptor source) async {
    if (BuiltInSources.findById(source.id) != null) {
      throw FormatException('无法使用内置图源保留 ID: ${source.id}');
    }
    final clean = source.copyWith(isBuiltIn: false);
    _customSources.removeWhere((e) => e.id == clean.id);
    _customSources.add(clean);
    _enabledOverrides[clean.id] = clean.isEnabled;
    if (_currentSourceId == clean.id) {
      _client?.close();
      _client = _buildClient(clean.id);
    }
    _syncImageHeaderRegistry();
    notifyListeners();
    await _saveConfig();
  }

  Future<void> removeCustomSource(String sourceId) async {
    final cleanId = sourceId.trim().toLowerCase();
    final before = _customSources.length;
    _customSources.removeWhere((e) => e.id == cleanId);
    if (_customSources.length == before) return;
    _enabledOverrides.remove(cleanId);
    _accounts.remove(cleanId);
    _healthStates.remove(cleanId);
    if (_currentSourceId == cleanId) {
      _currentSourceId = enabledSources.first.id;
      _client?.close();
      _client = _buildClient(_currentSourceId);
    }
    _syncImageHeaderRegistry();
    notifyListeners();
    await _saveConfig();
  }

  Future<void> updateCredentialsById(
    String sourceId, {
    String? username,
    String? userId,
    String? apiKey,
    String? cookies,
    String? userAgent,
  }) async {
    final cleanId = sourceId.trim().toLowerCase();
    final current = credentialsForSource(cleanId);
    final updated = current.copyWith(
      username: username,
      userId: userId,
      apiKey: apiKey,
      cookies: cookies,
      userAgent: userAgent,
    );
    _accounts[cleanId] = updated;
    if (cleanId == _currentSourceId) {
      _client?.close();
      _client = _buildClient(cleanId);
    }
    _syncImageHeaderRegistry();
    notifyListeners();
    await _saveConfig();
  }

  Future<void> clearCredentialsById(String sourceId) async {
    final cleanId = sourceId.trim().toLowerCase();
    _accounts.remove(cleanId);
    if (cleanId == _currentSourceId) {
      _client?.close();
      _client = _buildClient(cleanId);
    }
    _syncImageHeaderRegistry();
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
    await updateCredentialsById(
      site.name,
      username: username,
      apiKey: apiKey,
      cookies: cookies,
      userAgent: userAgent,
    );
  }

  Future<void> clearSiteCredentials(ImageSite site) async {
    await clearCredentialsById(site.name);
  }

  Future<void> setApiKey(String apiKey) async {
    await updateCredentialsById(currentSourceId, apiKey: apiKey);
  }

  Future<void> setUsername(String username) async {
    await updateCredentialsById(currentSourceId, username: username);
  }

  Future<SourceHealthState> testSourceConnection(String sourceId) async {
    final adapter = _buildClient(sourceId);
    final result = await adapter.testConnection();
    _healthStates[adapter.sourceId] = result;
    adapter.close();
    notifyListeners();
    return result;
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'currentSourceId': _currentSourceId,
        'safeMode': safeMode,
        'ratingFilter': _ratingFilter.name,
        'enabledOverrides': _enabledOverrides,
        'customSources':
            _customSources.map((s) => s.toJson(includeEnabledState: true)).toList(),
        'accounts': _accounts.map((k, v) => MapEntry(k, v.toJson())),
      };
      await prefs.setString(_registryKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Failed to save source config: $e');
    }
  }

  /// 供后台下载等无 BuildContext 场景按图源 ID 构建适配器并补充元数据。
  static Future<ImageSourceAdapter?> createAdapterForStoredSite(
    String siteId,
  ) async {
    final cleanId = siteId.trim().toLowerCase();
    if (cleanId.isEmpty) return null;
    SourceDescriptor? descriptor = BuiltInSources.findById(cleanId);
    var creds = const SourceAccountCredentials();
    try {
      final prefs = await SharedPreferences.getInstance();
      final v2Json = prefs.getString(_registryKey);
      if (v2Json != null && v2Json.isNotEmpty) {
        final decoded = jsonDecode(v2Json) as Map<String, dynamic>;
        if (descriptor == null) {
          final rawCustom = decoded['customSources'];
          if (rawCustom is List) {
            for (final item in rawCustom) {
              if (item is Map<String, dynamic> &&
                  (item['id']?.toString().toLowerCase() ?? '') == cleanId) {
                descriptor = SourceDescriptor.fromJson(item, isBuiltIn: false);
                break;
              }
            }
          }
        }
        final rawAccounts = decoded['accounts'];
        if (rawAccounts is Map &&
            rawAccounts[cleanId] is Map<String, dynamic>) {
          creds = SourceAccountCredentials.fromJson(
            rawAccounts[cleanId] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {}
    if (descriptor == null) return null;
    return SourceAdapterFactory.create(
      descriptor: descriptor,
      credentials: creds,
    );
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
