import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/api/danbooru_api_client.dart';
import 'package:vce1_sakuraview/api/yandere_api_client.dart';
import 'package:vce1_sakuraview/api/zerochan_api_client.dart';
import 'package:vce1_sakuraview/models/site_config.dart';

class ApiClientFactory {
  static ImageApiClient createClient(SiteConfig config) {
    switch (config.site) {
      case ImageSite.yandere:
        return YandereApiClient(
          apiKey: config.apiKey,
          username: config.username,
        );
      case ImageSite.danbooru:
        return DanbooruApiClient(
          apiKey: config.apiKey,
          username: config.username,
        );
      case ImageSite.zerochan:
        return ZerochanApiClient(
          apiKey: config.apiKey,
          username: config.username,
        );
    }
  }

  static String getSiteName(ImageSite site) => site.displayName;
}
