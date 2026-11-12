import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/api/danbooru_api_client.dart';
import 'package:vce1_sakuraview/api/yandere_api_client.dart';
import 'package:vce1_sakuraview/api/zerochan_api_client.dart';
import 'package:vce1_sakuraview/models/site_config.dart';

class ApiClientFactory {
  static ImageApiClient createClient(SiteConfig config) {
    final creds = config.credentialsFor(config.site);
    final username =
        creds.username.isNotEmpty ? creds.username : config.username;
    final apiKey = creds.apiKey.isNotEmpty ? creds.apiKey : config.apiKey;
    final cookies = creds.cookies.isNotEmpty ? creds.cookies : config.cookies;
    final userAgent =
        creds.userAgent.isNotEmpty ? creds.userAgent : config.userAgent;

    switch (config.site) {
      case ImageSite.yandere:
        return YandereApiClient(
          apiKey: apiKey,
          username: username,
          cookies: cookies,
          userAgent: userAgent,
        );
      case ImageSite.danbooru:
        return DanbooruApiClient(
          apiKey: apiKey,
          username: username,
          cookies: cookies,
          userAgent: userAgent,
        );
      case ImageSite.zerochan:
        return ZerochanApiClient(
          apiKey: apiKey,
          username: username,
          cookies: cookies,
          userAgent: userAgent,
        );
    }
  }

  static String getSiteName(ImageSite site) => site.displayName;
}
