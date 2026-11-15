import 'package:vce1_sakuraview/core/sources/adapters/zerochan_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';

/// 向后兼容导出，内部统一委托至 [ZerochanSourceAdapter]。
class ZerochanApiClient extends ZerochanSourceAdapter {
  ZerochanApiClient({
    String apiKey = '',
    String username = '',
    String cookies = '',
    String userAgent = '',
  }) : super(
          descriptor: BuiltInSources.findById('zerochan')!,
          credentials: SourceAccountCredentials(
            username: username,
            apiKey: apiKey,
            cookies: cookies,
            userAgent: userAgent,
          ),
        );

  static Map<String, dynamic>? extractZerochanJson(String rawBody) =>
      ZerochanSourceAdapter.extractZerochanJson(rawBody);
}
