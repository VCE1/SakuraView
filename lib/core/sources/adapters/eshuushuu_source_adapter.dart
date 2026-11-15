import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

/// E-Shuushuu 官方 FastAPI v1 适配器 (`/api/v1/images`, `/api/v1/tags`, `/api/v1/users`)。
///
/// 关键适配要点：
/// 1. `/api/v1/images` 仅接受数字 `tag_id`（`&tags=123,456&tags_mode=ALL`）与 `user_id`，
///    因此检索文本标签、画师或上传者前会自动查询 `/api/v1/tags` 与 `/api/v1/users` 解析 ID。
/// 2. 响应自带 4 种标签分类：`1=Theme(常规)`, `2=Source(原作)`, `3=Artist(画师)`, `4=Character(角色)`。
/// 3. 响应中的 `rating` 为 1-10 星级评分，内容安全分级严格标记为 `unknown`。
class EShuushuuSourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('EShuushuuSourceAdapter');
  static const String _cdnBase = 'https://cdn.e-shuushuu.net';

  const EShuushuuSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    final params = <String, String>{
      'page': '${query.page}',
      'per_page': '${query.limit.clamp(1, 50)}',
    };

    // 解析排序字段（如 favorites:desc / rating:desc / date_added:desc）
    final sort = (query.sort ?? '').trim();
    if (sort.contains(':')) {
      final parts = sort.split(':');
      params['sort'] = parts[0];
      params['sort_order'] = parts[1];
    } else {
      params['sort'] = 'date_added';
      params['sort_order'] = 'desc';
    }

    try {
      final extracted = ImageSourceAdapter.extractUploaderFromQuery(query);
      // 1. 解析上传者用户名 -> user_id
      final uploader = extracted.uploader;
      if (uploader.isNotEmpty) {
        final userId = await _resolveUserId(uploader);
        if (userId == null) {
          return const [];
        }
        params['user_id'] = userId.toString();
      }

      // 2. 解析标签文本与画师名 -> numeric tag_id（官方最多允许 5 个查询标签）
      final resolvedTagIds = <int>[];
      final rawTokens = extracted.remainingTags
          .trim()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .take(5)
          .toList();

      for (final token in rawTokens) {
        final numeric = int.tryParse(token);
        if (numeric != null && numeric > 0) {
          resolvedTagIds.add(numeric);
          continue;
        }
        final resolved = await _resolveTagId(token);
        if (resolved == null) {
          return const [];
        }
        resolvedTagIds.add(resolved);
      }

      final artist = query.artist?.trim() ?? '';
      if (artist.isNotEmpty && resolvedTagIds.length < 5) {
        final resolvedArtistId = await _resolveTagId(artist, preferredType: 3);
        if (resolvedArtistId == null) {
          return const [];
        }
        if (!resolvedTagIds.contains(resolvedArtistId)) {
          resolvedTagIds.add(resolvedArtistId);
        }
      }

      if (resolvedTagIds.isNotEmpty) {
        params['tags'] = resolvedTagIds.join(',');
        params['tags_mode'] = 'ALL';
      }

      final uri = buildUri('/api/v1/images', params);
      _logger.info('E-Shuushuu search: $uri');

      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'E-Shuushuu 请求失败 (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return parseImagesPayload(response.body);
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      throw ApiException('E-Shuushuu 返回数据格式异常', originalError: e);
    } catch (e) {
      throw ApiException('E-Shuushuu 加载失败: $e', originalError: e);
    }
  }

  Future<int?> _resolveUserId(String usernameQuery) async {
    final clean = usernameQuery.trim();
    if (clean.isEmpty) return null;
    final asInt = int.tryParse(clean);
    if (asInt != null && asInt > 0) return asInt;

    final uri = buildUri('/api/v1/users', {
      'search': clean,
      'per_page': '10',
    });
    final response = await httpGet(uri, timeout: const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final decoded = json.decode(response.body);
    final items = decoded is Map<String, dynamic>
        ? (decoded['users'] as List<dynamic>? ??
            decoded['items'] as List<dynamic>? ??
            const [])
        : (decoded is List ? decoded : const []);
    final lower = clean.toLowerCase();
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final name = (item['username'] ?? '').toString().trim().toLowerCase();
      if (name == lower) {
        return resolveInt(item['user_id']);
      }
    }
    if (items.isNotEmpty && items.first is Map<String, dynamic>) {
      return resolveInt((items.first as Map<String, dynamic>)['user_id']);
    }
    return null;
  }

  Future<int?> _resolveTagId(String rawTag, {int? preferredType}) async {
    final clean = rawTag.replaceAll('_', ' ').trim();
    if (clean.isEmpty) return null;

    final params = <String, String>{
      'search': clean,
      'exclude_aliases': 'true',
      'per_page': '15',
      if (preferredType != null) 'type': '$preferredType',
    };
    final uri = buildUri('/api/v1/tags', params);
    final response = await httpGet(uri, timeout: const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final decoded = json.decode(response.body);
    final items = decoded is Map<String, dynamic>
        ? (decoded['tags'] as List<dynamic>? ??
            decoded['items'] as List<dynamic>? ??
            const [])
        : (decoded is List ? decoded : const []);
    final lower = clean.toLowerCase();
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final title = (item['title'] ?? '').toString().trim().toLowerCase();
      if (title == lower) {
        return resolveInt(item['tag_id']);
      }
    }
    if (items.isNotEmpty && items.first is Map<String, dynamic>) {
      return resolveInt((items.first as Map<String, dynamic>)['tag_id']);
    }
    return null;
  }

  List<PostHiveModel> parseImagesPayload(String body) {
    final dynamic decoded = json.decode(body);
    final List<dynamic> items = decoded is Map<String, dynamic>
        ? (decoded['images'] as List<dynamic>? ??
            decoded['items'] as List<dynamic>? ??
            const [])
        : (decoded is List ? decoded : const []);
    final posts = <PostHiveModel>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final post = parsePost(item);
        if (post.id > 0) posts.add(post);
      } catch (e) {
        _logger.warning('E-Shuushuu parse failed: $e');
      }
    }
    return posts;
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final uri = buildUri('/api/v1/images/$id');
    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final target = decoded['image'] is Map<String, dynamic>
            ? decoded['image'] as Map<String, dynamic>
            : decoded;
        return parsePost(target);
      }
      return null;
    } catch (e) {
      _logger.warning('Failed to get E-Shuushuu post detail: $e');
      return null;
    }
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final clean = query.trim().replaceAll('_', ' ');
    if (clean.isEmpty) return const [];
    final uri = buildUri('/api/v1/tags', {
      'search': clean,
      'exclude_aliases': 'true',
      'per_page': '20',
    });
    try {
      final response = await httpGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(response.body);
      final items = decoded is Map<String, dynamic>
          ? (decoded['tags'] as List<dynamic>? ??
              decoded['items'] as List<dynamic>? ??
              const [])
          : (decoded is List ? decoded : const []);
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final title = (item['title'] ?? '').toString().trim();
            final type = resolveInt(item['type']) ?? 1;
            return TagSuggestion(
              value: title.replaceAll(' ', '_'),
              label: title,
              category: _mapTagType(type),
              postCount: resolveInt(item['usage_count'] ?? item['count']),
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (e) {
      _logger.fine('E-Shuushuu tag suggest failed: $e');
      return const [];
    }
  }

  String _mapTagType(int type) {
    switch (type) {
      case 2:
        return 'copyright';
      case 3:
        return 'artist';
      case 4:
        return 'character';
      default:
        return 'general';
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final id = resolveInt(json['image_id'] ?? json['id']) ?? 0;
    final filename = (json['filename'] as String? ?? '').trim();
    final ext = (json['ext'] as String? ?? 'jpg').trim().replaceAll('.', '');

    final thumbUrl = filename.isNotEmpty
        ? '$_cdnBase/thumbs/$filename.webp'
        : (resolveUrl(json, ['thumb_url', 'preview_url']) ?? '');
    final fullUrl = filename.isNotEmpty
        ? '$_cdnBase/fullsize/$filename.$ext'
        : (resolveUrl(json, ['file_url', 'url']) ?? '');
    final hasLarge = resolveInt(json['large']) == 1 || resolveBool(json['large']) == true;
    final hasMedium = resolveInt(json['medium']) == 1 || resolveBool(json['medium']) == true;
    final sampleUrl = filename.isNotEmpty
        ? (hasLarge
            ? '$_cdnBase/large/$filename.jpg'
            : (hasMedium ? '$_cdnBase/medium/$filename.jpg' : fullUrl))
        : (resolveUrl(json, ['sample_url']) ?? fullUrl);

    final userMap = json['user'] as Map<String, dynamic>?;
    final uploader = (userMap?['username'] as String? ?? '').trim();
    final uploaderId = resolveInt(userMap?['user_id']);

    final artists = <String>[];
    final characters = <String>[];
    final copyrights = <String>[];
    final generals = <String>[];

    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final item in rawTags) {
        if (item is! Map<String, dynamic>) continue;
        final title = (item['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        final token = title.replaceAll(RegExp(r'\s+'), '_');
        final type = resolveInt(item['type']) ?? 1;
        switch (type) {
          case 2:
            copyrights.add(token);
            break;
          case 3:
            artists.add(token);
            break;
          case 4:
            characters.add(token);
            break;
          default:
            generals.add(token);
            break;
        }
      }
    }

    final combinedTags = [
      ...copyrights,
      ...characterListOrEmpty(characters),
      ...artists,
      ...generals,
    ].join(' ');

    return PostHiveModel()
      ..id = id
      ..siteName = descriptor.id
      ..tags = combinedTags
      ..author = artists.isNotEmpty ? artists.join(', ') : null
      ..uploader = uploader.isNotEmpty ? uploader : null
      ..creatorId = uploaderId
      ..artistTags = artists.isEmpty ? null : artists
      ..characterTags = characters.isEmpty ? null : characters
      ..copyrightTags = copyrights.isEmpty ? null : copyrights
      ..generalTags = generals.isEmpty ? null : generals
      ..source = (json['source_url'] as String? ?? json['source'] as String? ?? '').trim()
      ..fileSize = resolveInt(json['filesize'] ?? json['file_size'])
      ..createdAt = resolveTimestamp(json['date_added'] ?? json['created_at'])
      // E-Shuushuu 的 rating 字段为星级评分，内容安全分级严格保留 unknown。
      ..rating = descriptor.normalizeRating(json['rating']).code
      ..score = (json['rating'] is num)
          ? (json['rating'] as num).round()
          : resolveInt(json['favorites']) ?? 0
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewUrl = thumbUrl.isNotEmpty ? thumbUrl : sampleUrl
      ..sampleUrl = sampleUrl.isNotEmpty ? sampleUrl : thumbUrl
      ..fileUrl = fullUrl.isNotEmpty ? fullUrl : sampleUrl
      ..fileExt = ext.isNotEmpty ? ext : 'jpg'
      ..hasChildren = false;
  }

  List<String> characterListOrEmpty(List<String> items) => items;
}
