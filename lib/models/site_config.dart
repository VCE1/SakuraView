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
        return 'https://zerochan.net';
    }
  }

  bool supportsPostDetailApi() {
    switch (this) {
      case ImageSite.danbooru:
      case ImageSite.yandere:
      case ImageSite.zerochan:
        return true;
    }
  }
}

class SiteConfig {
  final ImageSite site;
  final String apiKey;
  final String username;
  final bool safeMode;

  const SiteConfig({
    required this.site,
    this.apiKey = '',
    this.username = '',
    this.safeMode = false,
  });

  SiteConfig copyWith({
    ImageSite? site,
    String? apiKey,
    String? username,
    bool? safeMode,
  }) {
    return SiteConfig(
      site: site ?? this.site,
      apiKey: apiKey ?? this.apiKey,
      username: username ?? this.username,
      safeMode: safeMode ?? this.safeMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'site': site.index,
        'apiKey': apiKey,
        'username': username,
        'safeMode': safeMode,
      };

  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        site: ImageSite.values[json['site'] as int],
        apiKey: json['apiKey'] as String? ?? '',
        username: json['username'] as String? ?? '',
        safeMode: json['safeMode'] as bool? ?? false,
      );
}
