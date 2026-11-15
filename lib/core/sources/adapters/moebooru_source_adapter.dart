import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

/// 共享 Moebooru 协议适配器（统一服务 Yande.re、Konachan 与 Sakugabooru）。
///
/// 通过 `api_version=2&include_tags=1` 获取精准的标签分类字典，
/// 严格区分 `json['author']`（上传者 -> `uploader`）与 `tags[tag]=='artist'|'circle'`（画师 -> `artistTags`），
/// 并对 Sakugabooru 的 `.mp4` / `.webm` 视频原档做好预览图保护。
class MoebooruSourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('MoebooruSourceAdapter');

  const MoebooruSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

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
      final cleanArtist = artist.replaceAll(' ', '_');
      if (!tagTokens.contains(cleanArtist)) {
        tagTokens.add(cleanArtist);
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
          tagTokens.add('rating:s');
          break;
        case RatingFilterMode.r18:
          tagTokens.add('rating:e');
          break;
        case RatingFilterMode.all:
          break;
      }
    }

    final effectiveTags = tagTokens.join(' ');
    final queryParams = <String, String>{
      'api_version': '2',
      'include_tags': '1',
      'limit': '${query.limit}',
      'page': '${query.page}',
      if (effectiveTags.isNotEmpty) 'tags': effectiveTags,
    };

    final uri = buildUri('/post.json', queryParams);
    _logger.info('[${descriptor.id}] Moebooru search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          '${descriptor.name} 请求失败 (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return parsePostsPayload(response.body);
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      throw ApiException('${descriptor.name} 返回数据格式异常', originalError: e);
    } catch (e) {
      throw ApiException('${descriptor.name} 加载失败: $e', originalError: e);
    }
  }

  /// 解析 Moebooru v2 (`{"posts": [...], "tags": {...}}`) 或 v1 (`[...]`) 响应。
  List<PostHiveModel> parsePostsPayload(String body) {
    final dynamic decoded = json.decode(body);
    final Map<String, String> tagsDict = {};
    final List<dynamic> rawPosts;

    if (decoded is Map<String, dynamic>) {
      rawPosts = decoded['posts'] as List<dynamic>? ?? const [];
      final rawTagsMap = decoded['tags'];
      if (rawTagsMap is Map) {
        for (final entry in rawTagsMap.entries) {
          tagsDict[entry.key.toString().toLowerCase()] =
              entry.value.toString().toLowerCase();
        }
      }
    } else if (decoded is List) {
      rawPosts = decoded;
    } else {
      return const [];
    }

    final posts = <PostHiveModel>[];
    for (final item in rawPosts) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final post = parsePostWithTagDict(item, tagsDict);
        if (post.id > 0) posts.add(post);
      } catch (e) {
        _logger.warning(
          '[${descriptor.id}] failed to parse post id=${item['id'] ?? '?'}: $e',
        );
      }
    }
    return posts;
  }

  @override
  Future<List<PostHiveModel>> fetchCloudFavorites({
    int page = 1,
    int limit = 40,
    bool safeMode = false,
    RatingFilterMode? ratingFilter,
  }) async {
    final targetUser = username.trim();
    if (targetUser.isEmpty) {
      throw ApiException(
        '请先在站点设置中配置 ${descriptor.name} 用户名或通过 WebView 登录以同步收藏夹',
      );
    }
    return searchPosts(
      tags: 'vote:3:$targetUser order:vote',
      page: page,
      limit: limit,
      safeMode: safeMode,
      ratingFilter: ratingFilter,
    );
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final uri = buildUri('/post.json', {
      'api_version': '2',
      'include_tags': '1',
      'tags': 'id:$id',
      'limit': '1',
    });
    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return null;
      final list = parsePostsPayload(response.body);
      if (list.isEmpty) return null;
      final post = list.first;
      await _enrichCategoriesFromShowHtmlIfNeeded(post);
      return post;
    } catch (e) {
      _logger.warning('[${descriptor.id}] getPostDetail failed: $e');
      return null;
    }
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final clean = query.trim().replaceAll(' ', '_');
    if (clean.isEmpty) return const [];

    final uri = buildUri('/tag.json', {
      'name': '$clean*',
      'order': 'count',
      'limit': '20',
    });
    try {
      final response = await httpGet(uri, timeout: const Duration(seconds: 8));
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
              category: _mapTagType(item['type']),
              postCount: resolveInt(item['count']),
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (e) {
      _logger.fine('[${descriptor.id}] tag suggest failed: $e');
      return const [];
    }
  }

  String _mapTagType(dynamic rawType) {
    final t = resolveInt(rawType);
    switch (t) {
      case 1:
        return 'artist';
      case 3:
        return 'copyright';
      case 4:
        return 'character';
      case 5:
        return 'artist'; // circle
      default:
        return 'general';
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) =>
      parsePostWithTagDict(json, const {});

  PostHiveModel parsePostWithTagDict(
    Map<String, dynamic> json,
    Map<String, String> tagsDict,
  ) {
    final rawTags = (json['tags'] as String? ?? '').trim();
    final tokens = splitSpaceTags(rawTags);

    final artists = <String>[];
    final characters = <String>[];
    final copyrights = <String>[];
    final generals = <String>[];
    final metas = <String>[];

    if (tagsDict.isNotEmpty) {
      for (final tag in tokens) {
        final type = tagsDict[tag.toLowerCase()] ?? 'general';
        switch (type) {
          case 'artist':
          case 'circle':
            artists.add(tag);
            break;
          case 'character':
            characters.add(tag);
            break;
          case 'copyright':
            copyrights.add(tag);
            break;
          case 'style':
          case 'metadata':
          case 'meta':
          case 'faults':
            metas.add(tag);
            break;
          default:
            generals.add(tag);
            break;
        }
      }
    } else {
      generals.addAll(tokens);
    }

    // Moebooru 的 json['author'] 实际代表上传者账户名，严格归入 uploader，禁止冒充画师。
    final uploaderName = (json['author'] as String? ?? '').trim();

    final preview =
        resolveUrl(json, ['preview_url', 'preview_file_url']) ?? '';
    final rawSample =
        resolveUrl(json, ['sample_url', 'sample_file_url', 'jpeg_url']) ?? '';
    final rawFile = resolveUrl(json, ['file_url']) ?? '';
    final fileExt =
        (json['file_ext'] as String?) ?? extFromUrl(rawFile, fallback: 'jpg');

    final isVideoFile =
        SourceUrlResolver.isVideoMedia(url: rawFile, fileExt: fileExt);
    final isVideoSample =
        SourceUrlResolver.isVideoMedia(url: rawSample, fileExt: null);

    // 若为 MP4/WebM 动画片段，样本展示图绝不能直接传入 ImageProvider，应安全回退至静态 JPG 封面。
    final safeSample = (isVideoSample || rawSample.isEmpty)
        ? (preview.isNotEmpty ? preview : rawSample)
        : rawSample;

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..siteName = descriptor.id
      ..tags = rawTags
      ..author = artists.isNotEmpty ? artists.join(', ') : null
      ..uploader = uploaderName.isNotEmpty ? uploaderName : null
      ..creatorId = resolveInt(json['creator_id'])
      ..artistTags = artists.isEmpty ? null : artists
      ..characterTags = characters.isEmpty ? null : characters
      ..copyrightTags = copyrights.isEmpty ? null : copyrights
      ..generalTags = generals.isEmpty ? null : generals
      ..metaTags = metas.isEmpty ? null : metas
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size'])
      ..createdAt = resolveTimestamp(json['created_at'])
      ..rating = descriptor.normalizeRating(json['rating']).code
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewWidth =
          resolveInt(json['actual_preview_width'] ?? json['preview_width'])
      ..previewHeight =
          resolveInt(json['actual_preview_height'] ?? json['preview_height'])
      ..previewUrl = preview.isNotEmpty ? preview : safeSample
      ..sampleUrl = safeSample.isNotEmpty ? safeSample : preview
      ..fileUrl = rawFile.isNotEmpty && !isVideoFile
          ? rawFile
          : (rawFile.isNotEmpty ? rawFile : safeSample)
      ..fileExt = fileExt
      ..hasChildren = resolveBool(json['has_children'])
      ..parentId = resolveInt(json['parent_id']);
  }

  static final RegExp _showTagLiPattern = RegExp(
    r'<li\b[^>]*class=["\x27][^"\x27]*tag-type-(artist|circle|character|copyright|style|faults|metadata|meta|general)[^"\x27]*["\x27][^>]*>([\s\S]*?)</li>',
    caseSensitive: false,
  );
  static final RegExp _showAnchorPattern = RegExp(
    r'<a\b[^>]*href=["\x27]([^"\x27]*)["\x27][^>]*>([\s\S]*?)</a>',
    caseSensitive: false,
  );

  Future<void> _enrichCategoriesFromShowHtmlIfNeeded(PostHiveModel post) async {
    final noCategories = (post.artistTags?.isEmpty ?? true) &&
        (post.characterTags?.isEmpty ?? true) &&
        (post.copyrightTags?.isEmpty ?? true) &&
        (post.metaTags?.isEmpty ?? true);
    if (!noCategories || post.id <= 0 || splitSpaceTags(post.tags).isEmpty) {
      return;
    }

    try {
      final uri = buildUri('/post/show/${post.id}');
      final response = await httpGet(
        uri,
        headers: {
          ...headers,
          'Accept': 'text/html,application/xhtml+xml',
        },
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        enrichCategoriesFromShowHtml(post, response.body);
      }
    } catch (_) {}
  }

  /// 当 Moebooru `/post.json` 缺少 `tags` 分类映射时，从 `/post/show/<id>` HTML 侧边栏补充分类标签。
  static void enrichCategoriesFromShowHtml(PostHiveModel post, String html) {
    if (html.isEmpty) return;

    final artists = <String>[];
    final characters = <String>[];
    final copyrights = <String>[];
    final metas = <String>[];
    final generals = <String>[];
    final categorizedLower = <String>{};
    var foundAny = false;

    void addUnique(List<String> target, String token, {bool markCategorized = true}) {
      final normalized = ImageSourceAdapter.normalizeTagToken(token);
      if (normalized.isEmpty) return;
      final lower = normalized.toLowerCase();
      if (!target.any((e) => e.toLowerCase() == lower)) {
        target.add(normalized);
      }
      if (markCategorized) {
        categorizedLower.add(lower);
      }
    }

    for (final liMatch in _showTagLiPattern.allMatches(html)) {
      foundAny = true;
      final kind = (liMatch.group(1) ?? '').toLowerCase();
      final body = liMatch.group(2) ?? '';
      String resolved = '';

      for (final anchor in _showAnchorPattern.allMatches(body)) {
        final href = (anchor.group(1) ?? '').toLowerCase();
        final text = ImageSourceAdapter.decodeHtmlEntities(
          (anchor.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
        ).trim();
        if (text == '?' || text == '+' || text == '-' || href.contains('/wiki/')) {
          continue;
        }
        final m = RegExp(r'[?&]tags=([^&#\s]+)').firstMatch(anchor.group(1) ?? '');
        if (m != null) {
          try {
            resolved = ImageSourceAdapter.decodeHtmlEntities(
              Uri.decodeQueryComponent(m.group(1)!),
            ).trim();
          } catch (_) {}
        }
        if (resolved.isEmpty && text.isNotEmpty) {
          resolved = text;
        }
        if (resolved.isNotEmpty && !href.contains('/tag/')) {
          // 优先选用明确指向 /post?tags=... 的标签链接
          break;
        }
      }

      if (resolved.isEmpty) continue;
      switch (kind) {
        case 'artist':
        case 'circle':
          addUnique(artists, resolved);
          break;
        case 'character':
          addUnique(characters, resolved);
          break;
        case 'copyright':
          addUnique(copyrights, resolved);
          break;
        case 'style':
        case 'faults':
        case 'metadata':
        case 'meta':
          addUnique(metas, resolved);
          break;
        case 'general':
          addUnique(generals, resolved, markCategorized: false);
          break;
      }
    }

    if (!foundAny) return;
    if (artists.isNotEmpty) {
      post.artistTags = artists;
      post.author = artists.join(', ');
    }
    if (characters.isNotEmpty) post.characterTags = characters;
    if (copyrights.isNotEmpty) post.copyrightTags = copyrights;
    if (metas.isNotEmpty) post.metaTags = metas;

    final filteredGenerals = <String>[];
    final seenLower = <String>{};
    for (final token in [...(post.tags ?? '').split(RegExp(r'\s+')), ...generals]) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (!categorizedLower.contains(lower) && seenLower.add(lower)) {
        filteredGenerals.add(t);
      }
    }
    post.generalTags = filteredGenerals.isEmpty ? null : filteredGenerals;
  }
}
