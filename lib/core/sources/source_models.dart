import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/site_config.dart';

/// 图源协议引擎类型。
enum SourceEngineType {
  danbooru,
  moebooru,
  gelbooru,
  gelbooruXml,
  zerochan,
  eshuushuu,
  customBooruJson;

  String get displayName {
    switch (this) {
      case SourceEngineType.danbooru:
        return 'Danbooru v2';
      case SourceEngineType.moebooru:
        return 'Moebooru v2';
      case SourceEngineType.gelbooru:
        return 'Gelbooru DAPI (JSON)';
      case SourceEngineType.gelbooruXml:
        return 'Gelbooru DAPI (XML)';
      case SourceEngineType.zerochan:
        return 'Zerochan JSON';
      case SourceEngineType.eshuushuu:
        return 'E-Shuushuu API v1';
      case SourceEngineType.customBooruJson:
        return '自定义 JSON 扩展';
    }
  }

  static SourceEngineType fromName(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final v in SourceEngineType.values) {
      if (v.name.toLowerCase() == normalized) return v;
    }
    if (normalized == 'yandere' || normalized == 'konachan') {
      return SourceEngineType.moebooru;
    }
    if (normalized == 'gelbooru_xml') {
      return SourceEngineType.gelbooruXml;
    }
    if (normalized == 'e-shuushuu') {
      return SourceEngineType.eshuushuu;
    }
    return SourceEngineType.customBooruJson;
  }
}

/// 图源账号认证方式。
enum SourceAuthType {
  none,
  userApiKey,
  userIdApiKey,
  cookieOrUser,
  webCookie;

  static SourceAuthType fromName(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final v in SourceAuthType.values) {
      if (v.name.toLowerCase() == normalized) return v;
    }
    return SourceAuthType.none;
  }
}

/// 单项排序参数定义（严格按图源真实接口参数声明）。
class SourceSortOption {
  final String value;
  final String label;

  const SourceSortOption({
    required this.value,
    required this.label,
  });

  Map<String, dynamic> toJson() => {'value': value, 'label': label};

  factory SourceSortOption.fromJson(Map<String, dynamic> json) {
    return SourceSortOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? json['value']?.toString() ?? '',
    );
  }
}

/// 图源真实能力声明，用于在搜索与详情页动态匹配平台能力，绝不伪造不支持的筛选参数。
class SourceCapabilities {
  final bool supportsSafeMode;
  final bool supportsTagAutocomplete;
  final bool supportsUploaderFilter;
  final bool supportsArtistFilter;
  final bool supportsSort;
  final bool supportsCloudFavorites;
  final bool supportsVoting;
  final bool supportsGroups;
  final List<SourceSortOption> sortOptions;
  final String? uploaderHint;
  final String? artistHint;

  const SourceCapabilities({
    this.supportsSafeMode = true,
    this.supportsTagAutocomplete = false,
    this.supportsUploaderFilter = false,
    this.supportsArtistFilter = true,
    this.supportsSort = false,
    this.supportsCloudFavorites = false,
    this.supportsVoting = false,
    this.supportsGroups = false,
    this.sortOptions = const [],
    this.uploaderHint,
    this.artistHint,
  });

  Map<String, dynamic> toJson() => {
        'supportsSafeMode': supportsSafeMode,
        'supportsTagAutocomplete': supportsTagAutocomplete,
        'supportsUploaderFilter': supportsUploaderFilter,
        'supportsArtistFilter': supportsArtistFilter,
        'supportsSort': supportsSort,
        'supportsCloudFavorites': supportsCloudFavorites,
        'supportsVoting': supportsVoting,
        'supportsGroups': supportsGroups,
        'sortOptions': sortOptions.map((e) => e.toJson()).toList(),
        if (uploaderHint != null) 'uploaderHint': uploaderHint,
        if (artistHint != null) 'artistHint': artistHint,
      };

  factory SourceCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SourceCapabilities();
    final rawSorts = json['sortOptions'];
    final sorts = <SourceSortOption>[];
    if (rawSorts is List) {
      for (final item in rawSorts) {
        if (item is Map<String, dynamic>) {
          sorts.add(SourceSortOption.fromJson(item));
        }
      }
    }
    return SourceCapabilities(
      supportsSafeMode: json['supportsSafeMode'] as bool? ?? true,
      supportsTagAutocomplete: json['supportsTagAutocomplete'] as bool? ?? false,
      supportsUploaderFilter: json['supportsUploaderFilter'] as bool? ?? false,
      supportsArtistFilter: json['supportsArtistFilter'] as bool? ?? true,
      supportsSort: json['supportsSort'] as bool? ?? sorts.isNotEmpty,
      supportsCloudFavorites: json['supportsCloudFavorites'] as bool? ?? false,
      supportsVoting: json['supportsVoting'] as bool? ?? false,
      supportsGroups: json['supportsGroups'] as bool? ?? false,
      sortOptions: sorts,
      uploaderHint: json['uploaderHint'] as String?,
      artistHint: json['artistHint'] as String?,
    );
  }
}

/// 标签自动补全建议项。
class TagSuggestion {
  final String value;
  final String label;
  final String category;
  final int? postCount;

  const TagSuggestion({
    required this.value,
    String? label,
    this.category = 'general',
    this.postCount,
  }) : label = label ?? value;
}

/// 结构化搜索参数（由各站点适配器按自身协议拼接，而非统一硬编码前缀）。
class SourceSearchQuery {
  final String tags;
  final String? uploader;
  final String? artist;
  final int page;
  final int limit;
  final String? sort;
  final bool safeMode;
  final RatingFilterMode? ratingFilter;

  const SourceSearchQuery({
    this.tags = '',
    this.uploader,
    this.artist,
    this.page = 1,
    this.limit = 20,
    this.sort,
    this.safeMode = false,
    this.ratingFilter,
  });

  RatingFilterMode get effectiveRatingFilter =>
      ratingFilter ?? (safeMode ? RatingFilterMode.safe : RatingFilterMode.all);

  bool get hasExtraFilters =>
      (uploader != null && uploader!.trim().isNotEmpty) ||
      (artist != null && artist!.trim().isNotEmpty) ||
      (sort != null && sort!.trim().isNotEmpty);
}

/// 单图源运行健康状态（隔离记录每个图源的最近连通与错误，不互相影响）。
class SourceHealthState {
  final String sourceId;
  final bool isHealthy;
  final int? lastLatencyMs;
  final String? lastError;
  final DateTime? lastCheckedAt;

  const SourceHealthState({
    required this.sourceId,
    this.isHealthy = true,
    this.lastLatencyMs,
    this.lastError,
    this.lastCheckedAt,
  });
}

/// 参考 Venera 扩展清单元数据设计的图源描述模型，支持内置源、JSON 导入源及自定义源。
class SourceDescriptor {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final SourceEngineType engine;
  final String baseUrl;
  final String loginUrl;
  final String? refererUrl;
  final List<String> domainKeywords;
  final SourceAuthType authType;
  final String authDescription;
  final bool isBuiltIn;
  final bool defaultEnabled;
  final bool isEnabled;
  final SourceCapabilities capabilities;
  final Map<String, dynamic>? customConfig;

  const SourceDescriptor({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.author = 'SakuraView',
    this.description = '',
    required this.engine,
    required this.baseUrl,
    this.loginUrl = '',
    this.refererUrl,
    this.domainKeywords = const [],
    this.authType = SourceAuthType.none,
    this.authDescription = '',
    this.isBuiltIn = false,
    this.defaultEnabled = false,
    this.isEnabled = false,
    this.capabilities = const SourceCapabilities(),
    this.customConfig,
  });

  String get cleanBaseUrl => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  String get effectiveReferer {
    if (refererUrl != null && refererUrl!.trim().isNotEmpty) {
      return refererUrl!.trim();
    }
    return '$cleanBaseUrl/';
  }

  String get effectiveLoginUrl =>
      loginUrl.trim().isNotEmpty ? loginUrl.trim() : cleanBaseUrl;

  /// 将旧版 [ImageSite]（若匹配）映射到图源 ID，保持历史兼容。
  ImageSite? get legacyImageSite {
    switch (id.toLowerCase()) {
      case 'danbooru':
        return ImageSite.danbooru;
      case 'yandere':
        return ImageSite.yandere;
      case 'zerochan':
        return ImageSite.zerochan;
      default:
        return null;
    }
  }

  ContentRating normalizeRating(Object? raw) =>
      ContentRating.parse(raw, siteId: id);

  SourceDescriptor copyWith({
    String? name,
    String? version,
    String? author,
    String? description,
    SourceEngineType? engine,
    String? baseUrl,
    String? loginUrl,
    String? refererUrl,
    List<String>? domainKeywords,
    SourceAuthType? authType,
    String? authDescription,
    bool? isBuiltIn,
    bool? defaultEnabled,
    bool? isEnabled,
    SourceCapabilities? capabilities,
    Map<String, dynamic>? customConfig,
  }) {
    return SourceDescriptor(
      id: id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      engine: engine ?? this.engine,
      baseUrl: baseUrl ?? this.baseUrl,
      loginUrl: loginUrl ?? this.loginUrl,
      refererUrl: refererUrl ?? this.refererUrl,
      domainKeywords: domainKeywords ?? this.domainKeywords,
      authType: authType ?? this.authType,
      authDescription: authDescription ?? this.authDescription,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      defaultEnabled: defaultEnabled ?? this.defaultEnabled,
      isEnabled: isEnabled ?? this.isEnabled,
      capabilities: capabilities ?? this.capabilities,
      customConfig: customConfig ?? this.customConfig,
    );
  }

  Map<String, dynamic> toJson({bool includeEnabledState = true}) => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'engine': engine.name,
        'baseUrl': cleanBaseUrl,
        'loginUrl': loginUrl,
        if (refererUrl != null && refererUrl!.isNotEmpty)
          'refererUrl': refererUrl,
        'domainKeywords': domainKeywords,
        'authType': authType.name,
        'authDescription': authDescription,
        'defaultEnabled': defaultEnabled,
        if (includeEnabledState) 'isEnabled': isEnabled,
        'capabilities': capabilities.toJson(),
        if (customConfig != null) 'customConfig': customConfig,
      };

  factory SourceDescriptor.fromJson(
    Map<String, dynamic> json, {
    bool isBuiltIn = false,
    bool forceDisabledOnImport = false,
  }) {
    final id = (json['id'] ?? json['key'] ?? '').toString().trim().toLowerCase();
    final base = (json['baseUrl'] ?? json['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(base);
    final rawDomains = json['domainKeywords'];
    final keywords = <String>[
      if (rawDomains is List)
        ...rawDomains
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
      else if (uri != null && uri.host.isNotEmpty)
        uri.host.toLowerCase(),
    ];

    final defaultEnabledVal = json['defaultEnabled'] as bool? ?? false;
    final enabledVal = forceDisabledOnImport
        ? false
        : (json['isEnabled'] as bool? ?? defaultEnabledVal);

    return SourceDescriptor(
      id: id,
      name: (json['name'] ?? id).toString().trim(),
      version: (json['version'] ?? '1.0.0').toString().trim(),
      author: (json['author'] ?? 'Custom').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      engine: SourceEngineType.fromName(json['engine']?.toString()),
      baseUrl: base,
      loginUrl: (json['loginUrl'] ?? '').toString().trim(),
      refererUrl: json['refererUrl']?.toString().trim(),
      domainKeywords: keywords,
      authType: SourceAuthType.fromName(json['authType']?.toString()),
      authDescription: (json['authDescription'] ?? '').toString().trim(),
      isBuiltIn: isBuiltIn,
      defaultEnabled: forceDisabledOnImport ? false : defaultEnabledVal,
      isEnabled: enabledVal,
      capabilities: SourceCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>?,
      ),
      customConfig: json['customConfig'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['customConfig'] as Map)
          : null,
    );
  }
}

/// 图源账号认证信息（支持基于 String sourceId 的独立账户存储）。
class SourceAccountCredentials {
  final String username;
  final String userId;
  final String apiKey;
  final String cookies;
  final String userAgent;

  const SourceAccountCredentials({
    this.username = '',
    this.userId = '',
    this.apiKey = '',
    this.cookies = '',
    this.userAgent = '',
  });

  bool get hasApiAuth =>
      (username.trim().isNotEmpty || userId.trim().isNotEmpty) &&
      apiKey.trim().isNotEmpty;

  bool get hasCookieAuth => cookies.trim().isNotEmpty;

  bool get isConfigured =>
      username.trim().isNotEmpty ||
      userId.trim().isNotEmpty ||
      apiKey.trim().isNotEmpty ||
      cookies.trim().isNotEmpty;

  SourceAccountCredentials copyWith({
    String? username,
    String? userId,
    String? apiKey,
    String? cookies,
    String? userAgent,
  }) {
    return SourceAccountCredentials(
      username: username ?? this.username,
      userId: userId ?? this.userId,
      apiKey: apiKey ?? this.apiKey,
      cookies: cookies ?? this.cookies,
      userAgent: userAgent ?? this.userAgent,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'userId': userId,
        'apiKey': apiKey,
        'cookies': cookies,
        'userAgent': userAgent,
      };

  factory SourceAccountCredentials.fromJson(Map<String, dynamic> json) {
    return SourceAccountCredentials(
      username: json['username'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      cookies: json['cookies'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
    );
  }

  factory SourceAccountCredentials.fromLegacy(SiteAccountCredentials legacy) {
    return SourceAccountCredentials(
      username: legacy.username,
      apiKey: legacy.apiKey,
      cookies: legacy.cookies,
      userAgent: legacy.userAgent,
    );
  }

  SiteAccountCredentials toLegacy() => SiteAccountCredentials(
        username: username.isNotEmpty ? username : userId,
        apiKey: apiKey,
        cookies: cookies,
        userAgent: userAgent,
      );
}
