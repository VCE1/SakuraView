import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/services/webview_http_relay.dart';

/// Danbooru API v2 适配器。
class DanbooruSourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('DanbooruSourceAdapter');
  static const int _maxUserCacheSize = 512;
  static final Map<String, String> _uploaderCache = {};

  const DanbooruSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  @override
  Map<String, String> get headers {
    final cleanUser = username.trim();
    final map = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': userAgent.trim().isNotEmpty
          ? userAgent.trim()
          : (cleanUser.isNotEmpty && !cleanUser.contains('@')
              ? 'SakuraView/1.3 ($cleanUser)'
              : 'SakuraView/1.3 (booru-client)'),
      'Referer': descriptor.effectiveReferer,
    };
    if (cleanUser.isNotEmpty &&
        !cleanUser.contains('@') &&
        apiKey.trim().isNotEmpty) {
      final token = base64Encode(utf8.encode('$cleanUser:${apiKey.trim()}'));
      map['Authorization'] = 'Basic $token';
    }
    if (cookies.trim().isNotEmpty) {
      map['Cookie'] = cookies.trim();
    }
    return map;
  }

  Map<String, String> _withAuth(Map<String, String> params) {
    final cleanUser = username.trim();
    if (cleanUser.isNotEmpty &&
        !cleanUser.contains('@') &&
        apiKey.trim().isNotEmpty) {
      return {
        ...params,
        'login': cleanUser,
        'api_key': apiKey.trim(),
      };
    }
    return params;
  }

  static bool isCloudflareChallengeResponse(http.Response response) {
    if (response.statusCode != 403 && response.statusCode != 503) {
      return false;
    }
    final cfMitigated = response.headers['cf-mitigated']?.toLowerCase() ?? '';
    return cfMitigated == 'challenge' ||
        response.body.contains('Just a moment...') ||
        response.body.contains('challenges.cloudflare.com');
  }

  @override
  bool get hasWriteCredentials {
    final hasSession = cookies.trim().isNotEmpty;
    final hasBasic = username.trim().isNotEmpty &&
        !username.trim().contains('@') &&
        apiKey.trim().isNotEmpty;
    return hasSession || hasBasic;
  }

  /// 执行 Danbooru GET 请求；当移动端持有网页登录 Cookie 但 Dart HttpClient
  /// 因 TLS 指纹被 Cloudflare 拦截时，降级通过原生 WebView 同源通道执行请求。
  Future<http.Response> _danbooruGet(
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _danbooruRequest('GET', uri, timeout: timeout);

  Future<http.Response> _danbooruRequest(
    String method,
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final normalizedMethod = method.toUpperCase();
    final http.Response response;
    switch (normalizedMethod) {
      case 'POST':
        response = await httpPost(uri, timeout: timeout);
      case 'DELETE':
        response = await httpDelete(uri, timeout: timeout);
      default:
        response = await httpGet(uri, timeout: timeout);
    }

    final shouldRelay = WebViewHttpRelay.isSupported &&
        cookies.trim().isNotEmpty &&
        (isCloudflareChallengeResponse(response) ||
            (normalizedMethod != 'GET' &&
                (response.statusCode == 403 || response.statusCode == 422)));

    if (shouldRelay) {
      final relay = await WebViewHttpRelay.sendRequest(
        method: normalizedMethod,
        uri: uri,
        baseUrl: descriptor.cleanBaseUrl,
        cookies: cookies,
        userAgent: userAgent,
      );
      if (relay != null) {
        return http.Response(
          relay.body,
          relay.statusCode,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return response;
  }

  /// 从 `/profile.json` 解析当前已登录账号的 Danbooru 用户名与数字 ID。
  Future<({String name, String id})?> resolveAuthenticatedProfile() async {
    final hasSession = cookies.trim().isNotEmpty;
    final hasBasic = username.trim().isNotEmpty &&
        !username.trim().contains('@') &&
        apiKey.trim().isNotEmpty;
    if (!hasSession && !hasBasic) return null;

    final uri = buildUri('/profile.json', _withAuth({}));
    try {
      final response = await _danbooruGet(uri, timeout: const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return parseProfilePayload(json.decode(response.body));
    } catch (_) {
      return null;
    }
  }

  /// 解析 `/profile.json` 返回体，提取合法非匿名的 Danbooru 用户名与数字 ID。
  static ({String name, String id})? parseProfilePayload(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final rawId = decoded['id'];
    final id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString().trim() ?? '');
    final name = decoded['name']?.toString().trim() ?? '';
    if (name.isEmpty ||
        name.toLowerCase() == 'anonymous' ||
        (id != null && id <= 0)) {
      return null;
    }
    return (name: name, id: id != null ? '$id' : '');
  }

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    final tagTokens = <String>[];
    if (query.tags.trim().isNotEmpty) {
      tagTokens.addAll(
        query.tags
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty),
      );
    }

    final uploader = query.uploader?.trim() ?? '';
    if (uploader.isNotEmpty &&
        !tagTokens.any((t) => t.toLowerCase().startsWith('user:'))) {
      tagTokens.add('user:${uploader.replaceAll(' ', '_')}');
    }

    final artist = query.artist?.trim() ?? '';
    if (artist.isNotEmpty) {
      final normalizedArtist = artist.replaceAll(' ', '_');
      if (!tagTokens.contains(normalizedArtist)) {
        tagTokens.add(normalizedArtist);
      }
    }

    final sort = query.sort?.trim() ?? '';
    if (sort.isNotEmpty &&
        !tagTokens.any((t) => t.toLowerCase().startsWith('order:'))) {
      tagTokens.add(sort);
    }

    if (!tagTokens.any((t) => t.contains('rating:'))) {
      switch (query.effectiveRatingFilter) {
        case RatingFilterMode.safe:
          tagTokens.add('rating:general');
          break;
        case RatingFilterMode.r18:
          tagTokens.add('rating:explicit');
          break;
        case RatingFilterMode.all:
          break;
      }
    }

    final effectiveTags = tagTokens.join(' ');
    final queryParams = _withAuth(<String, String>{
      'limit': '${query.limit}',
      'page': '${query.page}',
      if (effectiveTags.isNotEmpty) 'tags': effectiveTags,
    });

    final uri = buildUri('/posts.json', queryParams);
    _logger.info('Danbooru search: $uri');

    try {
      final response = await _danbooruGet(uri);
      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw ApiException(
            'Danbooru 认证失败 (HTTP 401)：手动配置请填写官网「用户名 + API Key」（非登录密码）；如需使用账号密码登录请点击「网页登录」。',
            statusCode: 401,
          );
        }
        if (isCloudflareChallengeResponse(response)) {
          throw ApiException(
            'Danbooru 触发了 Cloudflare 验证拦截 (HTTP ${response.statusCode})。请在「账号与登录」中点击「网页登录」完成验证与登录后再试，或切换代理节点。',
            statusCode: response.statusCode,
          );
        }
        String? serverMsg;
        try {
          final errJson = json.decode(response.body);
          if (errJson is Map<String, dynamic>) {
            serverMsg = errJson['message']?.toString().trim();
          }
        } catch (_) {}
        if (response.statusCode == 422 &&
            serverMsg != null &&
            serverMsg.toLowerCase().contains('more than 2 tags')) {
          throw ApiException(
            '当前 Danbooru 账号每次最多支持 2 个搜索标签，请减少标签后重试，或登录更高权限账号。',
            statusCode: 422,
          );
        }
        throw ApiException(
          serverMsg != null && serverMsg.isNotEmpty
              ? 'Danbooru 请求失败 (${response.statusCode}): $serverMsg'
              : 'Danbooru 请求失败 (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      final dynamic decoded = json.decode(response.body);
      if (decoded is! List) return const [];
      final posts = <PostHiveModel>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final post = parsePost(item);
          if (post.id > 0 &&
              ((post.previewUrl?.isNotEmpty ?? false) ||
                  (post.sampleUrl?.isNotEmpty ?? false) ||
                  (post.fileUrl?.isNotEmpty ?? false))) {
            posts.add(post);
          }
        } catch (e) {
          _logger.warning(
            'Danbooru: failed to parse post id=${item['id'] ?? '?'}: $e',
          );
        }
      }
      await Future.wait([
        _enrichUploadersBatch(posts),
        _enrichPoolsBatch(posts),
      ]);
      return posts;
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      throw ApiException('Danbooru 返回数据格式异常', originalError: e);
    } catch (e) {
      throw ApiException('Danbooru 加载失败: $e', originalError: e);
    }
  }

  @override
  Future<List<PostHiveModel>> fetchCloudFavorites({
    int page = 1,
    int limit = 40,
    bool safeMode = false,
    RatingFilterMode? ratingFilter,
  }) async {
    var targetUser = username.trim();
    if (targetUser.isEmpty || targetUser.contains('@')) {
      final profile = await resolveAuthenticatedProfile();
      if (profile != null && profile.name.isNotEmpty) {
        targetUser = profile.name;
      }
    }

    if (targetUser.isEmpty) {
      throw ApiException(
        cookies.trim().isNotEmpty
            ? '未能从当前会话识别 Danbooru 用户名，请在「账号与登录」打开「网页登录」完成登录后重新保存，或手动填写用户名'
            : '请先在「账号与登录」通过网页登录，或填写 Danbooru 用户名以同步云端收藏夹',
      );
    }
    if (targetUser.contains('@')) {
      throw ApiException(
        'Danbooru 云端收藏同步仅支持官网「用户名」（不能使用邮箱作为用户名）。请通过「账号与登录 -> 网页登录」登录后保存会话，系统将自动识别您的用户名。',
      );
    }

    return searchPosts(
      tags: 'ordfav:${targetUser.replaceAll(' ', '_')}',
      page: page,
      limit: limit,
      safeMode: safeMode,
      ratingFilter: ratingFilter,
    );
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final uri = buildUri('/posts/$id.json', _withAuth({}));
    try {
      final response = await _danbooruGet(uri);
      if (response.statusCode != 200) {
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final post = parsePost(data);

      // Danbooru /posts/<id>.json 默认仅包含 uploader_id 且不包含 Pool 列表，并行补充上传者与画廊信息
      final tasks = <Future<void>>[
        _enrichPoolsBatch([post]),
      ];
      if ((post.uploader == null || post.uploader!.isEmpty) &&
          post.creatorId != null &&
          post.creatorId! > 0) {
        tasks.add(
          _lookupUploaderName(post.creatorId!).then((uploaderName) {
            if (uploaderName != null && uploaderName.isNotEmpty) {
              post.uploader = uploaderName;
            }
          }),
        );
      }
      await Future.wait(tasks);
      return post;
    } catch (e) {
      _logger.warning('Failed to get danbooru post detail: $e');
      return null;
    }
  }

  /// 解析 `/post_votes.json` 返回数组，提取当前用户对作品的投票分值（1 / -1 / 0）。
  static int parsePostVotePayload(dynamic decoded) {
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic> && item['is_deleted'] != true) {
          final score = item['score'];
          if (score is int) return score;
          return int.tryParse(score?.toString() ?? '') ?? 0;
        }
      }
      return 0;
    }
    if (decoded is Map<String, dynamic>) {
      if (decoded['is_deleted'] == true) return 0;
      final score = decoded['score'];
      if (score is int) return score;
      return int.tryParse(score?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  String _extractApiErrorMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final msg = (decoded['message'] ?? decoded['reason'] ?? decoded['error'])
            ?.toString()
            .trim();
        if (msg != null && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<int?> _fetchFreshPostScore(String postId) async {
    try {
      final uri = buildUri('/posts/$postId.json', _withAuth({'only': 'id,score'}));
      final res = await _danbooruGet(uri, timeout: const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = json.decode(res.body);
      if (decoded is Map<String, dynamic>) {
        return resolveInt(decoded['score']);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<({int userVote, int? postScore})?> fetchPostVoteState(
    String postId,
  ) async {
    if (!hasWriteCredentials) return null;
    final cleanId = postId.trim();
    if (cleanId.isEmpty) return null;
    try {
      final profile = await resolveAuthenticatedProfile();
      if (profile == null || profile.id.isEmpty) return null;
      final uri = buildUri(
        '/post_votes.json',
        _withAuth({
          'search[post_id]': cleanId,
          'search[user_id]': profile.id,
          'limit': '1',
        }),
      );
      final response =
          await _danbooruGet(uri, timeout: const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      return (userVote: parsePostVotePayload(decoded), postScore: null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({int userVote, int? postScore})?> votePost(
    String postId,
    int score,
  ) async {
    if (!hasWriteCredentials) {
      throw ApiException(
        '请先在「账号与登录」登录 Danbooru（支持网页登录或用户名 + API Key）',
        statusCode: 401,
      );
    }
    final voteVal = score >= 0 ? 1 : -1;
    final uri = buildUri(
      '/posts/${postId.trim()}/votes.json',
      _withAuth({'score': '$voteVal'}),
    );
    final response =
        await _danbooruRequest('POST', uri, timeout: const Duration(seconds: 15));
    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      final freshScore = await _fetchFreshPostScore(postId.trim());
      return (userVote: voteVal, postScore: freshScore);
    }
    if (response.statusCode == 422) {
      final msg = _extractApiErrorMessage(response).toLowerCase();
      if (msg.contains('already') || msg.contains('voted')) {
        final freshScore = await _fetchFreshPostScore(postId.trim());
        return (userVote: voteVal, postScore: freshScore);
      }
      throw ApiException(_extractApiErrorMessage(response), statusCode: 422);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        'Danbooru 认证失败或权限不足，请在「账号与登录」重新登录或检查用户名 + API Key',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      _extractApiErrorMessage(response),
      statusCode: response.statusCode,
    );
  }

  @override
  Future<({int userVote, int? postScore})?> unvotePost(String postId) async {
    if (!hasWriteCredentials) {
      throw ApiException(
        '请先在「账号与登录」登录 Danbooru（支持网页登录或用户名 + API Key）',
        statusCode: 401,
      );
    }
    final uri = buildUri(
      '/posts/${postId.trim()}/votes.json',
      _withAuth({}),
    );
    final response = await _danbooruRequest(
      'DELETE',
      uri,
      timeout: const Duration(seconds: 15),
    );
    if (response.statusCode == 200 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      final freshScore = await _fetchFreshPostScore(postId.trim());
      return (userVote: 0, postScore: freshScore);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        'Danbooru 认证失败或权限不足，请重新登录',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      _extractApiErrorMessage(response),
      statusCode: response.statusCode,
    );
  }

  @override
  Future<bool> addCloudFavorite(String postId) async {
    if (!hasWriteCredentials) {
      throw ApiException(
        '请先在「账号与登录」登录 Danbooru（支持网页登录或用户名 + API Key）',
        statusCode: 401,
      );
    }
    final uri = buildUri(
      '/favorites.json',
      _withAuth({'post_id': postId.trim()}),
    );
    final response =
        await _danbooruRequest('POST', uri, timeout: const Duration(seconds: 15));
    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      return true;
    }
    if (response.statusCode == 422 &&
        _extractApiErrorMessage(response).toLowerCase().contains('already')) {
      return true;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        'Danbooru 云端收藏授权失败，请重新登录或检查 API Key',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      _extractApiErrorMessage(response),
      statusCode: response.statusCode,
    );
  }

  @override
  Future<bool> removeCloudFavorite(String postId) async {
    if (!hasWriteCredentials) {
      throw ApiException(
        '请先在「账号与登录」登录 Danbooru（支持网页登录或用户名 + API Key）',
        statusCode: 401,
      );
    }
    final uri = buildUri(
      '/favorites/${postId.trim()}.json',
      _withAuth({}),
    );
    final response = await _danbooruRequest(
      'DELETE',
      uri,
      timeout: const Duration(seconds: 15),
    );
    if (response.statusCode == 200 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      return true;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        'Danbooru 云端取消收藏授权失败，请重新登录',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      _extractApiErrorMessage(response),
      statusCode: response.statusCode,
    );
  }

  /// 从 Danbooru `/users.json` 返回列表中解析 `userId -> username` 映射。
  static Map<int, String> parseUsersPayload(dynamic decoded) {
    if (decoded is! List) return const {};
    final resolved = <int, String>{};
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final rawId = item['id'];
      final id = rawId is int
          ? rawId
          : int.tryParse(rawId?.toString().trim() ?? '');
      final name = item['name']?.toString().trim() ?? '';
      if (id != null && id > 0 && name.isNotEmpty) {
        resolved[id] = name;
      }
    }
    return resolved;
  }

  String _cacheKey(int uploaderId) => '${descriptor.cleanBaseUrl}#$uploaderId';

  void _rememberUploader(int uploaderId, String name) {
    if (uploaderId <= 0 || name.isEmpty) return;
    if (_uploaderCache.length >= _maxUserCacheSize) {
      _uploaderCache.remove(_uploaderCache.keys.first);
    }
    _uploaderCache[_cacheKey(uploaderId)] = name;
  }

  /// 解析 Danbooru `/pools.json` 响应并回填对应帖子的 `poolId`、`poolName` 与 `poolIndex`。
  ///
  /// 优先匹配连续漫画/图集性质的 `series` 画廊；对小型 `collection`（<=24 张）作补充识别，
  /// 避免把上千张主题精选集误折叠成单张图组。
  static void applyPoolsPayload(List<PostHiveModel> posts, dynamic decoded) {
    if (decoded is! List || posts.isEmpty) return;
    final postsById = <int, PostHiveModel>{
      for (final p in posts)
        if (p.id > 0) p.id: p,
    };
    if (postsById.isEmpty) return;

    void bindPools({required bool seriesOnly}) {
      for (final rawPool in decoded) {
        if (rawPool is! Map<String, dynamic>) continue;
        final category =
            (rawPool['category']?.toString() ?? '').trim().toLowerCase();
        if (seriesOnly && category != 'series') continue;
        if (!seriesOnly && category == 'series') continue;

        final rawPoolId = rawPool['id'];
        final poolId = rawPoolId is int
            ? rawPoolId
            : int.tryParse(rawPoolId?.toString() ?? '') ?? 0;
        if (poolId <= 0) continue;

        final rawIds = rawPool['post_ids'];
        if (rawIds is! List || rawIds.isEmpty) continue;
        final poolIds = <int>[];
        for (final entry in rawIds) {
          final parsed =
              entry is int ? entry : int.tryParse(entry?.toString() ?? '') ?? 0;
          if (parsed > 0) poolIds.add(parsed);
        }
        final declaredCount = rawPool['post_count'] is int
            ? rawPool['post_count'] as int
            : int.tryParse(rawPool['post_count']?.toString() ?? '') ??
                poolIds.length;
        final effectiveCount =
            declaredCount > poolIds.length ? declaredCount : poolIds.length;
        if (effectiveCount < 2) continue;
        if (!seriesOnly && effectiveCount > 24) continue;

        final poolName = (rawPool['name']?.toString() ?? '')
            .replaceAll('_', ' ')
            .trim();

        for (var idx = 0; idx < poolIds.length; idx++) {
          final post = postsById[poolIds[idx]];
          if (post == null) continue;
          if (post.poolId != null && post.poolId! > 0) continue;
          post.poolId = poolId;
          post.poolName = poolName.isNotEmpty ? poolName : 'Pool #$poolId';
          post.poolIndex = idx;
        }
      }
    }

    bindPools(seriesOnly: true);
    bindPools(seriesOnly: false);
  }

  /// 批量反查帖子所属的 Danbooru Pool（画廊），解决 `/posts.json` 默认不附带 `pools` 字段的问题。
  ///
  /// 注意：`search[post_ids_include_any]` 必须使用空格分隔的 ID 列表，逗号分隔会被截断为首项。
  Future<void> _enrichPoolsBatch(List<PostHiveModel> posts) async {
    final targetIds = <int>[
      for (final p in posts)
        if (p.id > 0 && (p.poolId == null || p.poolId! <= 0)) p.id,
    ];
    if (targetIds.isEmpty) return;

    for (var i = 0; i < targetIds.length; i += 40) {
      final chunk = targetIds.sublist(i, (i + 40).clamp(0, targetIds.length));
      try {
        final uri = buildUri(
          '/pools.json',
          _withAuth({
            'search[post_ids_include_any]': chunk.join(' '),
            'search[is_deleted]': 'false',
            'only': 'id,name,category,post_ids,post_count',
            'limit': '50',
          }),
        );
        final response = await _danbooruGet(
          uri,
          timeout: const Duration(seconds: 6),
        );
        if (response.statusCode != 200) continue;
        applyPoolsPayload(posts, json.decode(response.body));
      } catch (_) {
        // Pool 反查超时或受限时静默降级，不阻塞主页/搜索展示
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchGroupPosts(
    Map<String, dynamic> postMap,
  ) async {
    final id = (postMap['id'] as num?)?.toInt() ??
        int.tryParse(postMap['id']?.toString() ?? '') ??
        0;
    final parentId = (postMap['parent_id'] as num?)?.toInt() ??
        int.tryParse(postMap['parent_id']?.toString() ?? '') ??
        0;
    final hasChildren = postMap['has_children'] == true;
    final poolId = (postMap['pool_id'] as num?)?.toInt() ??
        int.tryParse(postMap['pool_id']?.toString() ?? '') ??
        0;
    final poolName = (postMap['pool_name']?.toString() ?? '').trim();
    final pixivId = (postMap['pixiv_id'] as num?)?.toInt() ??
        int.tryParse(postMap['pixiv_id']?.toString() ?? '') ??
        0;
    final groupSource = (postMap['group_source']?.toString() ?? '').trim();

    final hasParentTree = (parentId > 0 && parentId != id) || hasChildren;
    final rootId = parentId > 0 ? parentId : id;

    final poolFuture = poolId > 0
        ? searchPosts(tags: 'ordpool:$poolId', limit: 100)
        : Future.value(const <PostHiveModel>[]);
    final parentFuture = (hasParentTree && rootId > 0)
        ? searchPosts(tags: 'parent:$rootId', limit: 100)
        : Future.value(const <PostHiveModel>[]);
    final pixivFuture = (poolId <= 0 && !hasParentTree && groupSource == 'pixiv' && pixivId > 0)
        ? searchPosts(tags: 'pixiv:$pixivId', limit: 50)
        : Future.value(const <PostHiveModel>[]);

    final results = await Future.wait([
      poolFuture,
      parentFuture,
      pixivFuture,
    ]);

    final poolPosts = results[0];
    final parentPosts = results[1];
    final pixivPosts = results[2];

    final seenIds = <int>{};
    final ordered = <Map<String, dynamic>>[];

    void appendModel(PostHiveModel model, {bool fromPool = false}) {
      if (model.id <= 0 || !seenIds.add(model.id)) return;
      if (fromPool && poolId > 0) {
        model.poolId ??= poolId;
        if ((model.poolName == null || model.poolName!.isEmpty) &&
            poolName.isNotEmpty) {
          model.poolName = poolName;
        }
      }
      ordered.add(model.toApiMap(siteName: descriptor.id));
    }

    // Pool 画廊保持作者编排的 ordpool 顺序；父子帖组将母帖置首后按 ID 升序
    for (final p in poolPosts) {
      appendModel(p, fromPool: true);
    }

    if (parentPosts.isNotEmpty) {
      final sortedParents = List<PostHiveModel>.from(parentPosts)
        ..sort((a, b) {
          if (a.id == rootId && b.id != rootId) return -1;
          if (b.id == rootId && a.id != rootId) return 1;
          return a.id.compareTo(b.id);
        });
      for (final p in sortedParents) {
        appendModel(p);
      }
    }

    if (pixivPosts.isNotEmpty) {
      final sortedPixiv = List<PostHiveModel>.from(pixivPosts)
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final p in sortedPixiv) {
        appendModel(p);
      }
    }

    return ordered;
  }

  /// 为 `/posts.json` 列表按 `uploader_id` 批量反查上传者名称（只写入 uploader）。
  Future<void> _enrichUploadersBatch(List<PostHiveModel> posts) async {
    if (posts.isEmpty) return;
    final missingIds = <int>{};
    for (final post in posts) {
      if (post.uploader != null && post.uploader!.isNotEmpty) continue;
      final uid = post.creatorId;
      if (uid == null || uid <= 0) continue;
      final cached = _uploaderCache[_cacheKey(uid)];
      if (cached != null && cached.isNotEmpty) {
        post.uploader = cached;
      } else {
        missingIds.add(uid);
      }
    }
    if (missingIds.isEmpty) return;

    final idList = missingIds.toList();
    for (int i = 0; i < idList.length; i += 100) {
      final chunk = idList.sublist(i, (i + 100).clamp(0, idList.length));
      try {
        final uri = buildUri(
          '/users.json',
          _withAuth({
            'search[id]': chunk.join(','),
            'limit': '${chunk.length}',
          }),
        );
        final response = await _danbooruGet(
          uri,
          timeout: const Duration(seconds: 6),
        );
        if (response.statusCode != 200) continue;
        final resolved = parseUsersPayload(json.decode(response.body));
        if (resolved.isEmpty) continue;
        for (final entry in resolved.entries) {
          _rememberUploader(entry.key, entry.value);
        }
        for (final post in posts) {
          if ((post.uploader == null || post.uploader!.isEmpty) &&
              post.creatorId != null) {
            final name = resolved[post.creatorId!];
            if (name != null && name.isNotEmpty) {
              post.uploader = name;
            }
          }
        }
      } catch (_) {
        // 批量反查失败或遭遇拦截时降级保留 creatorId，不影响列表正常展示
      }
    }
  }

  Future<String?> _lookupUploaderName(int uploaderId) async {
    final cached = _uploaderCache[_cacheKey(uploaderId)];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final uri = buildUri('/users/$uploaderId.json', _withAuth({}));
      final response = await _danbooruGet(
        uri,
        timeout: const Duration(seconds: 6),
      );
      if (response.statusCode != 200) return null;
      final map = json.decode(response.body);
      if (map is Map<String, dynamic>) {
        final name = map['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          _rememberUploader(uploaderId, name);
          return name;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    try {
      final uri = buildUri(
        '/autocomplete.json',
        _withAuth({
          'search[query]': clean,
          'search[type]': 'tag_query',
          'limit': '20',
        }),
      );
      final response = await _danbooruGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((item) {
                final val = item['value']?.toString() ??
                    item['name']?.toString() ??
                    '';
                final label = item['label']?.toString() ?? val;
                final cat = _mapCategory(item['category']);
                final count = resolveInt(item['post_count']);
                return TagSuggestion(
                  value: val,
                  label: label,
                  category: cat,
                  postCount: count,
                );
              })
              .where((e) => e.value.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      _logger.fine('Danbooru autocomplete fallback triggered: $e');
    }

    try {
      final uri = buildUri(
        '/tags.json',
        _withAuth({'search[name_matches]': '$clean*', 'limit': '20'}),
      );
      final response = await _danbooruGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final name = item['name']?.toString() ?? '';
            return TagSuggestion(
              value: name,
              label: name,
              category: _mapCategory(item['category']),
              postCount: resolveInt(item['post_count']),
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _mapCategory(dynamic raw) {
    final code = resolveInt(raw);
    switch (code) {
      case 1:
        return 'artist';
      case 3:
        return 'copyright';
      case 4:
        return 'character';
      case 5:
        return 'meta';
      default:
        final str = (raw ?? '').toString().toLowerCase();
        if (str.contains('artist')) return 'artist';
        if (str.contains('copyright')) return 'copyright';
        if (str.contains('character')) return 'character';
        if (str.contains('meta')) return 'meta';
        return 'general';
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final file = json['file'] as Map<String, dynamic>? ?? {};
    final preview = json['preview'] as Map<String, dynamic>? ?? {};
    final largeFile = json['large_file'] as Map<String, dynamic>? ?? {};

    String? variantPreviewUrl;
    String? variantSampleUrl;
    String? variantOriginalUrl;
    int? previewW;
    int? previewH;
    final mediaAsset = json['media_asset'];
    if (mediaAsset is Map<String, dynamic>) {
      final variants = mediaAsset['variants'];
      if (variants is List) {
        for (final v in variants) {
          if (v is! Map<String, dynamic>) continue;
          final type = v['type'] as String? ?? '';
          final url = ensureHttps(v['url'] as String? ?? '');
          if (url.isEmpty) continue;
          if (type == '360x360') {
            variantPreviewUrl = url;
            previewW = resolveInt(v['width']);
            previewH = resolveInt(v['height']);
          } else if (type == '180x180' && variantPreviewUrl == null) {
            variantPreviewUrl = url;
            previewW = resolveInt(v['width']);
            previewH = resolveInt(v['height']);
          } else if (type == 'sample' || type == '720x720') {
            variantSampleUrl ??= url;
          } else if (type == 'original') {
            variantOriginalUrl = url;
          }
        }
      }
    }

    String firstNonEmpty(Iterable<String?> candidates) {
      for (final c in candidates) {
        if (c != null && c.trim().isNotEmpty) return c.trim();
      }
      return '';
    }

    final resolvedPreview = firstNonEmpty([
      resolveUrl(json, ['preview_file_url', 'preview_url']),
      ensureHttps(preview['url'] as String?),
      variantPreviewUrl,
    ]);
    final resolvedFile = firstNonEmpty([
      resolveUrl(json, ['file_url']),
      ensureHttps(file['url'] as String?),
      variantOriginalUrl,
    ]);
    final resolvedSample = firstNonEmpty([
      resolveUrl(json, ['large_file_url', 'sample_url']),
      ensureHttps(largeFile['url'] as String?),
      variantSampleUrl,
      resolvedFile,
    ]);

    final rawTagStr =
        (json['tag_string'] as String?) ?? (json['tags'] as String?) ?? '';
    final uploaderName = (json['uploader'] is Map)
        ? (json['uploader']['name'] as String? ?? '').trim()
        : (json['uploader_name'] as String? ?? '').trim();

    final artists = splitSpaceTags(json['tag_string_artist'] as String?);
    final characters = splitSpaceTags(json['tag_string_character'] as String?);
    final copyrights = splitSpaceTags(json['tag_string_copyright'] as String?);
    final generals = splitSpaceTags(json['tag_string_general'] as String?);
    final metas = splitSpaceTags(json['tag_string_meta'] as String?);

    final finalGeneral = generals.isNotEmpty
        ? generals
        : (artists.isEmpty && characters.isEmpty && copyrights.isEmpty
            ? splitSpaceTags(rawTagStr)
            : const <String>[]);

    final effectivePreview =
        resolvedPreview.isNotEmpty ? resolvedPreview : resolvedSample;
    final effectiveSample =
        resolvedSample.isNotEmpty ? resolvedSample : effectivePreview;
    final effectiveFile =
        resolvedFile.isNotEmpty ? resolvedFile : effectiveSample;

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..siteName = descriptor.id
      ..tags = rawTagStr.trim()
      ..author = artists.isNotEmpty ? artists.join(', ') : null
      ..uploader = uploaderName.isNotEmpty ? uploaderName : null
      ..creatorId = resolveInt(json['uploader_id'])
      ..artistTags = artists.isEmpty ? null : artists
      ..characterTags = characters.isEmpty ? null : characters
      ..copyrightTags = copyrights.isEmpty ? null : copyrights
      ..generalTags = finalGeneral.isEmpty ? null : finalGeneral
      ..metaTags = metas.isEmpty ? null : metas
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size']) ?? resolveInt(file['size'])
      ..createdAt = resolveTimestamp(json['created_at'])
      ..rating = descriptor.normalizeRating(json['rating']).code
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['image_width']) ?? resolveInt(json['width']) ?? 0
      ..height =
          resolveInt(json['image_height']) ?? resolveInt(json['height']) ?? 0
      ..previewWidth = previewW
      ..previewHeight = previewH
      ..previewUrl = effectivePreview
      ..sampleUrl = effectiveSample
      ..fileUrl = effectiveFile
      ..fileExt = (json['file_ext'] as String?) ??
          (file['ext'] as String?) ??
          extFromUrl(effectiveFile)
      ..hasChildren = resolveBool(json['has_visible_children']) ??
          resolveBool(json['has_active_children']) ??
          resolveBool(json['has_children'])
      ..parentId = resolveInt(json['parent_id'])
      ..pixivId = resolveInt(json['pixiv_id']);
  }
}
