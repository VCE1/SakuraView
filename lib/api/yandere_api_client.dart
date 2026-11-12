import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:logging/logging.dart';

class YandereApiClient extends ImageApiClient {
  YandereApiClient({super.apiKey, super.username})
      : super(site: ImageSite.yandere);

  static final _logger = Logger('YandereApiClient');

  @override
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
      };

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
      tagParts.add('rating:s');
    }
    final effectiveTags = tagParts.join(' ');

    final queryParams = <String, String>{
      'limit': '$limit',
      'page': '$page',
      if (effectiveTags.isNotEmpty) 'tags': effectiveTags,
    };

    final uri = buildUri('/post.json', queryParams);
    _logger.info('Yande.re search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'Yande.re returned ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final List<dynamic> data = json.decode(response.body);
      final posts = <PostHiveModel>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final post = parsePost(item);
          if (post.id > 0) posts.add(post);
        } catch (e) {
          _logger.warning('Yande.re: failed to parse post id=${item['id'] ?? '?'}: $e');
        }
      }
      return posts;
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
    final uri = buildUri('/post.json', {'tags': 'id:$id', 'limit': '1'});
    _logger.info('Yande.re post detail: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'Yande.re returned ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final List<dynamic> data = json.decode(response.body);
      if (data.isEmpty) return null;
      return parsePost(data.first as Map<String, dynamic>);
    } catch (e) {
      _logger.warning('Failed to get yande.re post detail: $e');
      return null;
    }
  }

  @override
  Future<List<String>> searchTags(String query) async {
    final uri = buildUri('/tag.json', {'name_pattern': query, 'limit': '20'});
    _logger.info('Yande.re tag search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return [];
      final List<dynamic> data = json.decode(response.body);
      return data
          .map((item) => item['name'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      _logger.warning('Yande.re tag search failed: $e');
      return [];
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final rawTags = json['tags'] as String? ?? '';
    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..tags = rawTags.trim()
      ..author = json['author'] as String? ?? 'unknown'
      ..creatorId = resolveInt(json['creator_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size'])
      ..createdAt = resolveTimestamp(json['created_at'])
      ..rating = json['rating'] as String? ?? 's'
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewUrl = resolveUrl(json, ['preview_url', 'preview_file_url']) ??
          (json['preview_url'] as String? ?? '')
      ..sampleUrl = resolveUrl(json, ['sample_url', 'sample_file_url']) ??
          (json['sample_url'] as String? ?? '')
      ..fileUrl = json['file_url'] as String? ?? ''
      ..fileExt = json['file_ext'] as String? ??
          _extFromUrl(json['file_url'] as String? ?? '')
      ..hasChildren = resolveBool(json['has_children']);
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
