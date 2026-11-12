enum ImageSite { danbooru, yandere, zerochan }

extension ImageSiteExtension on ImageSite {
  String get displayName {
    switch (this) {
      case ImageSite.danbooru:
        return 'Danbooru';
      case ImageSite.yandere:
        return 'Yande.re';
      case ImageSite.zerochan:
        return 'Zerochan';
    }
  }

  String get apiBaseUrl {
    switch (this) {
      case ImageSite.danbooru:
        return 'https://danbooru.donmai.us';
      case ImageSite.yandere:
        return 'https://yande.re';
      case ImageSite.zerochan:
        return 'https://www.zerochan.net';
    }
  }

  String get loginUrl {
    switch (this) {
      case ImageSite.danbooru:
        return 'https://danbooru.donmai.us/session/new';
      case ImageSite.yandere:
        return 'https://yande.re/user/login';
      case ImageSite.zerochan:
        return 'https://www.zerochan.net/login';
    }
  }

  String get domainKeyword {
    switch (this) {
      case ImageSite.danbooru:
        return 'donmai.us';
      case ImageSite.yandere:
        return 'yande.re';
      case ImageSite.zerochan:
        return 'zerochan.net';
    }
  }

  String get authDescription {
    switch (this) {
      case ImageSite.danbooru:
        return '支持用户名 + API Key 认证或 WebView 登录保存 Cookie，登录后可同步 Danbooru 云端收藏夹';
      case ImageSite.yandere:
        return '支持 WebView 登录保存 Cookie 或配置用户名，可同步 Yande.re 三星收藏夹 (vote:3:<用户名>)';
      case ImageSite.zerochan:
        return '支持 WebView 登录保存 Cookie 或配置会员名，可同步 Zerochan 云端收藏并访问会员原图';
    }
  }

  bool supportsPostDetailApi() => true;
}

/// Independent credentials & session cookies for a single [ImageSite].
class SiteAccountCredentials {
  final String username;
  final String apiKey;
  final String cookies;
  final String userAgent;

  const SiteAccountCredentials({
    this.username = '',
    this.apiKey = '',
    this.cookies = '',
    this.userAgent = '',
  });

  bool get hasApiAuth => username.trim().isNotEmpty && apiKey.trim().isNotEmpty;
  bool get hasCookieAuth => cookies.trim().isNotEmpty;
  bool get isConfigured =>
      username.trim().isNotEmpty ||
      apiKey.trim().isNotEmpty ||
      cookies.trim().isNotEmpty;

  SiteAccountCredentials copyWith({
    String? username,
    String? apiKey,
    String? cookies,
    String? userAgent,
  }) {
    return SiteAccountCredentials(
      username: username ?? this.username,
      apiKey: apiKey ?? this.apiKey,
      cookies: cookies ?? this.cookies,
      userAgent: userAgent ?? this.userAgent,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'apiKey': apiKey,
        'cookies': cookies,
        'userAgent': userAgent,
      };

  factory SiteAccountCredentials.fromJson(Map<String, dynamic> json) {
    return SiteAccountCredentials(
      username: json['username'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      cookies: json['cookies'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
    );
  }
}

class SiteConfig {
  final ImageSite site;
  final String apiKey;
  final String username;
  final String cookies;
  final String userAgent;
  final bool safeMode;
  final Map<ImageSite, SiteAccountCredentials> accounts;

  const SiteConfig({
    required this.site,
    this.apiKey = '',
    this.username = '',
    this.cookies = '',
    this.userAgent = '',
    this.safeMode = false,
    this.accounts = const {},
  });

  SiteAccountCredentials credentialsFor(ImageSite target) {
    final stored = accounts[target];
    if (stored != null) return stored;
    if (target == site) {
      return SiteAccountCredentials(
        username: username,
        apiKey: apiKey,
        cookies: cookies,
        userAgent: userAgent,
      );
    }
    return const SiteAccountCredentials();
  }

  SiteConfig copyWith({
    ImageSite? site,
    String? apiKey,
    String? username,
    String? cookies,
    String? userAgent,
    bool? safeMode,
    Map<ImageSite, SiteAccountCredentials>? accounts,
  }) {
    final nextSite = site ?? this.site;
    final nextAccounts = Map<ImageSite, SiteAccountCredentials>.from(
      accounts ?? this.accounts,
    );
    final activeCreds = nextAccounts[nextSite];
    return SiteConfig(
      site: nextSite,
      apiKey: apiKey ?? activeCreds?.apiKey ?? this.apiKey,
      username: username ?? activeCreds?.username ?? this.username,
      cookies: cookies ?? activeCreds?.cookies ?? this.cookies,
      userAgent: userAgent ?? activeCreds?.userAgent ?? this.userAgent,
      safeMode: safeMode ?? this.safeMode,
      accounts: nextAccounts,
    );
  }

  Map<String, dynamic> toJson() {
    final accountsJson = <String, dynamic>{};
    for (final entry in accounts.entries) {
      accountsJson[entry.key.name] = entry.value.toJson();
    }
    return {
      'site': site.index,
      'apiKey': apiKey,
      'username': username,
      'cookies': cookies,
      'userAgent': userAgent,
      'safeMode': safeMode,
      'accounts': accountsJson,
    };
  }

  factory SiteConfig.fromJson(Map<String, dynamic> json) {
    final siteIndex = (json['site'] as int? ?? 1).clamp(0, ImageSite.values.length - 1);
    final activeSite = ImageSite.values[siteIndex];
    final legacyUser = json['username'] as String? ?? '';
    final legacyKey = json['apiKey'] as String? ?? '';
    final legacyCookies = json['cookies'] as String? ?? '';
    final legacyUa = json['userAgent'] as String? ?? '';

    final parsedAccounts = <ImageSite, SiteAccountCredentials>{};
    final rawAccounts = json['accounts'];
    if (rawAccounts is Map<String, dynamic>) {
      for (final s in ImageSite.values) {
        final item = rawAccounts[s.name];
        if (item is Map<String, dynamic>) {
          parsedAccounts[s] = SiteAccountCredentials.fromJson(item);
        }
      }
    }

    if (!parsedAccounts.containsKey(activeSite) &&
        (legacyUser.isNotEmpty || legacyKey.isNotEmpty || legacyCookies.isNotEmpty)) {
      parsedAccounts[activeSite] = SiteAccountCredentials(
        username: legacyUser,
        apiKey: legacyKey,
        cookies: legacyCookies,
        userAgent: legacyUa,
      );
    }

    final currentCreds =
        parsedAccounts[activeSite] ?? const SiteAccountCredentials();

    return SiteConfig(
      site: activeSite,
      apiKey: currentCreds.apiKey.isNotEmpty ? currentCreds.apiKey : legacyKey,
      username:
          currentCreds.username.isNotEmpty ? currentCreds.username : legacyUser,
      cookies: currentCreds.cookies.isNotEmpty
          ? currentCreds.cookies
          : legacyCookies,
      userAgent:
          currentCreds.userAgent.isNotEmpty ? currentCreds.userAgent : legacyUa,
      safeMode: json['safeMode'] as bool? ?? true,
      accounts: parsedAccounts,
    );
  }
}
