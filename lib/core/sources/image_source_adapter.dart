import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';

/// 统一图源适配器契约（参考 Venera 图源扩展隔离设计）。
///
/// 每个内置源或第三方 JSON 导入源均实现此接口；单源网络失败、认证缺失或
/// 数据异常仅隔离作用于该适配器本身，不会影响其他图源与首页核心体验。
abstract class ImageSourceAdapter {
  static final Logger _log = Logger('ImageSourceAdapter');

  final SourceDescriptor descriptor;
  final SourceAccountCredentials credentials;

  const ImageSourceAdapter({
    required this.descriptor,
    this.credentials = const SourceAccountCredentials(),
  });

  String get sourceId => descriptor.id;
  ImageSite get site => descriptor.legacyImageSite ?? ImageSite.yandere;
  SourceCapabilities get capabilities => descriptor.capabilities;

  String get username => credentials.username;
  String get userId => credentials.userId;
  String get apiKey => credentials.apiKey;
  String get cookies => credentials.cookies;
  String get userAgent => credentials.userAgent;

  bool get hasAccountConfigured => credentials.isConfigured;

  Map<String, String> get headers {
    final map = <String, String>{
      'Accept': 'application/json',
      'User-Agent': userAgent.trim().isNotEmpty
          ? userAgent.trim()
          : 'vce1.sakuraview/1.2 (vce1)',
      'Referer': descriptor.effectiveReferer,
    };
    if (cookies.trim().isNotEmpty) {
      map['Cookie'] = cookies.trim();
    }
    return map;
  }

  /// 构建针对本图源 [SourceDescriptor.baseUrl] 的安全请求 URI。
  Uri buildUri(String path, [Map<String, String>? queryParams]) {
    final base = Uri.parse(descriptor.cleanBaseUrl);
    final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final effectivePath = basePath.isEmpty ? cleanPath : '$basePath$cleanPath';
    return base.replace(
      path: effectivePath,
      queryParameters: (queryParams == null || queryParams.isEmpty)
          ? null
          : queryParams,
    );
  }

  /// 当前适配器是否具备可写（点赞/云端收藏）认证凭据。
  bool get hasWriteCredentials => false;

  Future<http.Response> _sendHttpRequest(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final effectiveHeaders = headers ?? this.headers;
    _log.fine('[${descriptor.id}] $method $uri');

    final client = await ProxyConfig.createClient();
    final sw = Stopwatch()..start();
    try {
      final Future<http.Response> future;
      switch (method.toUpperCase()) {
        case 'POST':
          future = client.post(uri, headers: effectiveHeaders, body: body);
        case 'DELETE':
          future = client.delete(uri, headers: effectiveHeaders, body: body);
        case 'PUT':
          future = client.put(uri, headers: effectiveHeaders, body: body);
        default:
          future = client.get(uri, headers: effectiveHeaders);
      }
      final response = await future.timeout(timeout);
      sw.stop();
      _log.fine(
        '[${descriptor.id}] => HTTP ${response.statusCode} (${sw.elapsedMilliseconds}ms)',
      );
      return response;
    } catch (e, st) {
      sw.stop();
      _log.warning(
        '[${descriptor.id}] => FAIL after ${sw.elapsedMilliseconds}ms: $e\n$st',
      );
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<http.Response> httpGet(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _sendHttpRequest('GET', uri, headers: headers, timeout: timeout);

  Future<http.Response> httpPost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _sendHttpRequest(
        'POST',
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );

  Future<http.Response> httpDelete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _sendHttpRequest(
        'DELETE',
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );

  /// 主检索入口：由各站点适配器依据自身真实接口参数组装搜索条件。
  Future<List<PostHiveModel>> searchPostsWithQuery(SourceSearchQuery query);

  /// 兼容旧版平铺调用签名，内部委托至 [searchPostsWithQuery]。
  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
    bool safeMode = false,
    RatingFilterMode? ratingFilter,
    String? uploader,
    String? artist,
  }) {
    final resolvedFilter = ratingFilter ??
        (safeMode ? RatingFilterMode.safe : RatingFilterMode.all);
    return searchPostsWithQuery(
      SourceSearchQuery(
        tags: tags ?? '',
        uploader: uploader,
        artist: artist,
        page: page,
        limit: limit,
        sort: sort,
        safeMode: resolvedFilter.isSafe,
        ratingFilter: resolvedFilter,
      ),
    );
  }

  /// 获取结构化标签联想建议（含分类与计数）。
  Future<List<TagSuggestion>> suggestTags(String query) async => const [];

  /// 兼容旧版仅返回字符串列表的标签检索调用。
  Future<List<String>> searchTags(String query) async {
    final suggestions = await suggestTags(query);
    return suggestions.map((e) => e.value).toList();
  }

  /// 获取单条帖子完整详情（用于补全标签分类、原图地址与元数据）。
  Future<PostHiveModel?> getPostDetail(String id);

  /// 拉取云端收藏夹（仅在 [SourceCapabilities.supportsCloudFavorites] 为真时有效）。
  Future<List<PostHiveModel>> fetchCloudFavorites({
    int page = 1,
    int limit = 40,
    bool safeMode = false,
    RatingFilterMode? ratingFilter,
  }) async {
    return const [];
  }

  /// 查询当前登录账号对指定作品的评分投票状态（1=点赞，-1=点踩，0=未投票）。
  Future<({int userVote, int? postScore})?> fetchPostVoteState(
    String postId,
  ) async =>
      null;

  /// 对指定作品提交评分投票（`score` 为 `1` 或 `-1`）。
  Future<({int userVote, int? postScore})?> votePost(
    String postId,
    int score,
  ) async =>
      throw UnsupportedError('${descriptor.name} 不支持作品评分');

  /// 取消当前账号对指定作品的评分投票。
  Future<({int userVote, int? postScore})?> unvotePost(String postId) async =>
      throw UnsupportedError('${descriptor.name} 不支持取消评分');

  /// 将作品同步加入站点云端收藏夹。
  Future<bool> addCloudFavorite(String postId) async =>
      throw UnsupportedError('${descriptor.name} 不支持云端收藏写入');

  /// 从站点云端收藏夹移除指定作品。
  Future<bool> removeCloudFavorite(String postId) async =>
      throw UnsupportedError('${descriptor.name} 不支持取消云端收藏');

  /// 拉取关联图组（父子帖）。
  Future<List<Map<String, dynamic>>> fetchChildPosts(int parentId) async {
    if (!descriptor.capabilities.supportsGroups) {
      return const [];
    }
    try {
      final posts = await searchPosts(tags: 'parent:$parentId', limit: 100);
      return posts.map((p) => p.toApiMap(siteName: descriptor.id)).toList();
    } catch (e) {
      _log.warning('[${descriptor.id}] fetchChildPosts($parentId) failed: $e');
      return const [];
    }
  }

  /// 拉取完整关联图组（兼容父子关系、画廊 Pool 与多页组）。
  Future<List<Map<String, dynamic>>> fetchGroupPosts(
    Map<String, dynamic> postMap,
  ) async {
    final rawId = postMap['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final rawParent = postMap['parent_id'] ?? postMap['parentId'];
    final parentId = rawParent is int
        ? rawParent
        : int.tryParse(rawParent?.toString() ?? '') ?? 0;
    final rootId = parentId > 0 ? parentId : id;
    if (rootId <= 0) return const [];
    return fetchChildPosts(rootId);
  }

  /// 连通性与配置自检（在「图源管理」内单独测试当前图源，异常隔离）。
  Future<SourceHealthState> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      await searchPosts(page: 1, limit: 1);
      sw.stop();
      return SourceHealthState(
        sourceId: descriptor.id,
        isHealthy: true,
        lastLatencyMs: sw.elapsedMilliseconds,
        lastCheckedAt: DateTime.now(),
      );
    } catch (e) {
      sw.stop();
      return SourceHealthState(
        sourceId: descriptor.id,
        isHealthy: false,
        lastLatencyMs: sw.elapsedMilliseconds,
        lastError: e.toString().replaceFirst('ApiException: ', ''),
        lastCheckedAt: DateTime.now(),
      );
    }
  }

  Future<void> close() async {}

  @protected
  PostHiveModel parsePost(Map<String, dynamic> json);

  @protected
  String? resolveUrl(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value is String && value.trim().isNotEmpty) {
        return SourceUrlResolver.ensureHttpsUrl(
          value,
          baseUrl: descriptor.cleanBaseUrl,
        );
      }
    }
    return null;
  }

  @protected
  String ensureHttps(String? raw) =>
      SourceUrlResolver.ensureHttpsUrl(raw, baseUrl: descriptor.cleanBaseUrl);

  @protected
  String normalizeTags(String? rawTags) {
    if (rawTags == null || rawTags.isEmpty) return '';
    return rawTags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.trim())
        .join(' ');
  }

  @protected
  int? resolveInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @protected
  int? resolveTimestamp(dynamic value) {
    final asInt = resolveInt(value);
    if (asInt != null) return asInt;
    if (value is String && value.isNotEmpty) {
      final dt = DateTime.tryParse(value);
      if (dt != null) {
        return dt.millisecondsSinceEpoch ~/ 1000;
      }
    }
    return null;
  }

  @protected
  bool? resolveBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == 'true' || lower == '1';
    }
    return null;
  }

  @protected
  int resolveScore(dynamic score) {
    if (score is Map<String, dynamic>) {
      return resolveInt(score['up']) ?? resolveInt(score['total']) ?? 0;
    }
    return resolveInt(score) ?? 0;
  }

  @protected
  String extFromUrl(String url, {String fallback = 'jpg'}) {
    if (url.isEmpty) return fallback;
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url.split('?').first;
    final dotIdx = path.lastIndexOf('.');
    if (dotIdx == -1 || dotIdx == path.length - 1) return fallback;
    final ext = path.substring(dotIdx + 1).toLowerCase();
    if (ext.length <= 5) return ext;
    return fallback;
  }

  @protected
  List<String> splitSpaceTags(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static final RegExp _quotedUserTokenPattern = RegExp(
    r'(?:^|\s)user:"([^"]+)"',
    caseSensitive: false,
  );
  static final RegExp _userQueryTokenPattern = RegExp(
    r'^user:(.+)$',
    caseSensitive: false,
  );

  /// 从搜索查询的空格分隔词条中提取 `user:<uploader>`，并与 [SourceSearchQuery.uploader] 合并。
  static ({String uploader, String remainingTags}) extractUploaderFromQuery(
    SourceSearchQuery query,
  ) {
    var uploader = query.uploader?.trim() ?? '';
    var working = query.tags.trim();
    final quoted = _quotedUserTokenPattern.firstMatch(working);
    if (quoted != null) {
      final extracted = quoted.group(1)?.trim() ?? '';
      if (uploader.isEmpty && extracted.isNotEmpty) {
        uploader = extracted;
      }
      working = working.replaceFirst(quoted.group(0)!, ' ').trim();
    }

    final remaining = <String>[];
    for (final token
        in working.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      final m = _userQueryTokenPattern.firstMatch(token);
      if (m != null) {
        final extracted = m.group(1)?.trim() ?? '';
        if (uploader.isEmpty && extracted.isNotEmpty) {
          uploader = extracted;
        }
      } else {
        remaining.add(token);
      }
    }
    return (uploader: uploader, remainingTags: remaining.join(' '));
  }

  /// 将展示文本中的空白规整为统一的下划线标签格式。
  static String normalizeTagToken(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '_');

  /// 解码常见 HTML 命名实体与数字字符实体。
  static String decodeHtmlEntities(String input) {
    if (!input.contains('&')) return input;
    var out = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    if (out.contains('&#')) {
      out = out.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (m) {
        final raw = m.group(1)!;
        final code = raw.startsWith('x') || raw.startsWith('X')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        if (code != null && code > 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return m.group(0)!;
      });
    }
    return out;
  }
}
