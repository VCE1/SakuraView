import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/source_adapter_factory.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
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

    final descriptor = BuiltInSources.findById(config.site.name) ??
        BuiltInSources.catalog.first;

    return SourceAdapterFactory.create(
      descriptor: descriptor,
      credentials: SourceAccountCredentials(
        username: username,
        apiKey: apiKey,
        cookies: cookies,
        userAgent: userAgent,
      ),
    );
  }

  static String getSiteName(ImageSite site) => site.displayName;
}
