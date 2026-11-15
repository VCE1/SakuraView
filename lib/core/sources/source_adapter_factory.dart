import 'package:vce1_sakuraview/core/sources/adapters/custom_json_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/eshuushuu_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/gelbooru_family_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/moebooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/zerochan_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';

/// 根据 [SourceDescriptor.engine] 构建对应的隔离图源适配器实例。
class SourceAdapterFactory {
  SourceAdapterFactory._();

  static ImageSourceAdapter create({
    required SourceDescriptor descriptor,
    SourceAccountCredentials credentials = const SourceAccountCredentials(),
  }) {
    switch (descriptor.engine) {
      case SourceEngineType.danbooru:
        return DanbooruSourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
      case SourceEngineType.moebooru:
        return MoebooruSourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
      case SourceEngineType.gelbooru:
      case SourceEngineType.gelbooruXml:
        return GelbooruFamilySourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
      case SourceEngineType.zerochan:
        return ZerochanSourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
      case SourceEngineType.eshuushuu:
        return EShuushuuSourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
      case SourceEngineType.customBooruJson:
        return CustomJsonSourceAdapter(
          descriptor: descriptor,
          credentials: credentials,
        );
    }
  }
}
