/// 图源扩展开发模板（面向社区或开发者导入/适配新图源）。
class SourceDeveloperTemplate {
  SourceDeveloperTemplate._();

  /// 标准 JSON 清单模板，可直接在「图源管理 -> JSON 导入」中修改后导入测试。
  static const String jsonTemplate = '''{
  "id": "custom_moebooru_demo",
  "name": "示例 Moebooru 图站",
  "version": "1.0.0",
  "author": "Community",
  "description": "兼容 Moebooru /posts 或自定义 JSON REST 接口的声明式图源模板",
  "engine": "moebooru",
  "baseUrl": "https://example-booru.org",
  "loginUrl": "https://example-booru.org/user/login",
  "authType": "cookieOrUser",
  "authDescription": "可选配置用户名或通过 WebView 登录保存 Cookie",
  "defaultEnabled": false,
  "capabilities": {
    "supportsSafeMode": true,
    "supportsTagAutocomplete": true,
    "supportsUploaderFilter": true,
    "supportsArtistFilter": true,
    "supportsSort": true,
    "supportsCloudFavorites": false,
    "supportsGroups": true,
    "sortOptions": [
      { "value": "order:id_desc", "label": "最新" },
      { "value": "order:score", "label": "高分" }
    ]
  },
  "customConfig": {
    "searchPath": "/post.json",
    "detailPath": "/post.json",
    "autocompletePath": "/tag.json",
    "tagsParam": "tags",
    "pageParam": "page",
    "limitParam": "limit",
    "autocompleteParam": "name_pattern",
    "safeModeTag": "rating:s",
    "itemsPath": "",
    "fieldMap": {
      "id": "id",
      "previewUrl": "preview_url",
      "sampleUrl": "sample_url",
      "fileUrl": "file_url",
      "width": "width",
      "height": "height",
      "tags": "tags",
      "uploader": "author",
      "rating": "rating",
      "source": "source",
      "parentId": "parent_id",
      "hasChildren": "has_children",
      "score": "score"
    }
  }
}''';

  /// Dart 适配器开发骨架（供内置或二次开发新增复杂站点适配器参考）。
  static const String dartAdapterSkeleton = '''// 实现 ImageSourceAdapter 即可接入任意站点接口，单源故障与注册状态完全隔离。
class MyCustomSourceAdapter extends ImageSourceAdapter {
  MyCustomSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(SourceSearchQuery query) async {
    // 1. 按站点真实 API 拼接 query.tags / query.uploader / query.artist / query.safeMode
    // 2. 使用 httpGet(uri) 自动复用全局网络代理与自定义 Cookie/User-Agent
    // 3. 调用 descriptor.normalizeRating(rawRating) 确保未知分级保持 unknown
    // 4. 上传者写入 uploader，真实画师写入 artistTags，切勿混用
    throw UnimplementedError();
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async => const [];

  @override
  Future<PostHiveModel?> getPostDetail(String id) async => null;

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) => throw UnimplementedError();
}''';
}
