import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:logging/logging.dart';

class DanbooruApiClient extends ImageApiClient {
  DanbooruApiClient({super.apiKey, super.username})
      : super(site: ImageSite.danbooru);

  static final _logger = Logger('DanbooruApiClient');

  @override
  Map<String, String> get headers {
    final map = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': username.isNotEmpty
          ? 'vce1.sakuraview/1.1 ($username)'
          : 'vce1.sakuraview/1.1 (vce1)',
    };
    if (username.isNotEmpty && apiKey.isNotEmpty) {
      final token = base64Encode(utf8.encode('$username:$apiKey'));
      map['Authorization'] = 'Basic $token';
    }
    return map;
  }

  Map<String, String> _withAuth(Map<String, String> params) {
    if (username.isNotEmpty && apiKey.isNotEmpty) {
      return {
        ...params,
        'login': username,
        'api_key': apiKey,
      };
    }
    return params;
  }

  @override
  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
    bool safeMode = false,
  }) async {
    final tagParts = <String>[];
    if (tags != null && tags.trim().isNotEmpty) {
      tagParts.add(tags.trim());
    }
    if (safeMode && !tagParts.any((t) => t.contains('rating:'))) {
      tagParts.add('rating:general');
    }
    final effectiveTags = tagParts.join(' ');

    final queryParams = _withAuth(<String, String>{
      'limit': '$limit',
      'page': '$page',
      if (effectiveTags.isNotEmpty) 'tags': effectiveTags,
      if (sort != null) 'search[sort]': sort,
    });

    final uri = buildUri('/posts.json', queryParams);
    _logger.info('Danbooru search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        final isCfChallenge = response.statusCode == 403 &&
            (response.headers['cf-mitigated'] == 'challenge' ||
                response.body.contains('Just a moment...') ||
                response.body.contains('challenges.cloudflare.com'));
        if (isCfChallenge) {
          throw ApiException(
            'Danbooru 触发了 Cloudflare 验证拦截 (HTTP 403)。请在设置中配置 Danbooru 用户名与 API Key，或切换代理节点。',
            statusCode: 403,
          );
        }
        throw ApiException(
          'Danbooru 请求失败 (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      final List<dynamic> data = json.decode(response.body);
      final posts = <PostHiveModel>[];
      for (final item in data) {
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
          _logger.warning('Danbooru: failed to parse post id=${item['id'] ?? '?'}: $e');
        }
      }
      return posts;
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      throw ApiException('Invalid response data', originalError: e);
    } catch (e) {
      throw ApiException('Failed to fetch posts', originalError: e);
    }
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final uri = buildUri('/posts/$id.json', _withAuth({}));
    _logger.info('Danbooru post detail: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'Danbooru returned ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      return parsePost(data);
    } catch (e) {
      _logger.warning('Failed to get danbooru post detail: $e');
      return null;
    }
  }

  @override
  Future<List<String>> searchTags(String query) async {
    final uri = buildUri(
      '/tags.json',
      _withAuth({'search[name_matches]': '$query*', 'limit': '20'}),
    );
    _logger.info('Danbooru tag search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return [];
      final List<dynamic> data = json.decode(response.body);
      return data
          .map((item) => item['name'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      _logger.warning('Danbooru tag search failed: $e');
      return [];
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final file = json['file'] as Map<String, dynamic>? ?? {};
    final preview = json['preview'] as Map<String, dynamic>? ?? {};
    final largeFile = json['large_file'] as Map<String, dynamic>? ?? {};

    // Also inspect media_asset.variants from Danbooru API v2
    String? variantPreviewUrl;
    String? variantSampleUrl;
    String? variantOriginalUrl;
    final mediaAsset = json['media_asset'];
    if (mediaAsset is Map<String, dynamic>) {
      final variants = mediaAsset['variants'];
      if (variants is List) {
        for (final v in variants) {
          if (v is! Map<String, dynamic>) continue;
          final type = v['type'] as String? ?? '';
          final url = v['url'] as String? ?? '';
          if (url.isEmpty) continue;
          if (type == '360x360') {
            variantPreviewUrl = url;
          } else if (type == '180x180' && variantPreviewUrl == null) {
            variantPreviewUrl = url;
          } else if (type == 'sample' || type == '720x720') {
            variantSampleUrl ??= url;
          } else if (type == 'original') {
            variantOriginalUrl = url;
          }
        }
      }
    }

    final resolvedPreview = resolveUrl(json, ['preview_file_url', 'preview_url']) ??
        (preview['url'] as String?) ??
        variantPreviewUrl ??
        '';
    final resolvedFile = resolveUrl(json, ['file_url']) ??
        (file['url'] as String?) ??
        variantOriginalUrl ??
        '';
    final resolvedSample = resolveUrl(json, ['large_file_url', 'sample_url']) ??
        (largeFile['url'] as String?) ??
        variantSampleUrl ??
        resolvedFile;

    final rawTagStr = (json['tag_string'] as String?) ?? (json['tags'] as String?) ?? '';
    final uploaderName = (json['uploader'] is Map)
        ? (json['uploader']['name'] as String?)
        : null;
    final artistTag = (json['tag_string_artist'] as String?)?.trim();
    final resolvedAuthor = (uploaderName != null && uploaderName.isNotEmpty)
        ? uploaderName
        : (artistTag != null && artistTag.isNotEmpty ? artistTag : 'unknown');

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..tags = rawTagStr.trim()
      ..author = resolvedAuthor
      ..creatorId = resolveInt(json['uploader_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size']) ?? resolveInt(file['size'])
      ..createdAt = resolveTimestamp(json['created_at'])
      ..rating = json['rating'] as String? ?? 'q'
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['image_width']) ?? resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['image_height']) ?? resolveInt(json['height']) ?? 0
      ..previewUrl = resolvedPreview.isNotEmpty ? resolvedPreview : resolvedSample
      ..sampleUrl = resolvedSample.isNotEmpty ? resolvedSample : resolvedPreview
      ..fileUrl = resolvedFile.isNotEmpty ? resolvedFile : resolvedSample
      ..fileExt = (json['file_ext'] as String?) ??
          (file['ext'] as String?) ??
          _extFromUrl(resolvedFile)
      ..hasChildren = resolveBool(json['has_children']) ??
          resolveBool(json['has_active_children']);
  }

  String _extFromUrl(String url) {
    if (url.isEmpty) return 'jpg';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return 'jpg';
    final ext = uri.pathSegments.last.split('.').lastOrNull;
    if (ext != null && ext.length <= 5) return ext;
    return 'jpg';
  }
}
