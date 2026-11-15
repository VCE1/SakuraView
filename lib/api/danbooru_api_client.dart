import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';

/// 向后兼容导出，内部统一委托至 [DanbooruSourceAdapter]。
class DanbooruApiClient extends DanbooruSourceAdapter {
  DanbooruApiClient({
    String apiKey = '',
    String username = '',
    String cookies = '',
    String userAgent = '',
  }) : super(
          descriptor: BuiltInSources.findById('danbooru')!,
          credentials: SourceAccountCredentials(
            username: username,
            apiKey: apiKey,
            cookies: cookies,
            userAgent: userAgent,
          ),
        );
}
