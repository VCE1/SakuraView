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
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'User-Agent':
            username.isNotEmpty ? 'vce1.sakuraview/1.0 ($username)' : 'vce1.sakuraview/1.0',
      };

  @override
  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'page': '$page',
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (sort != null) 'search[sort]': sort,
    };

    final uri = buildUri('/posts.json', queryParams);
    _logger.info('Danbooru search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'Danbooru returned ${response.statusCode}',
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
          _logger.warning('Danbooru: failed to parse post id=${item['id'] ?? '?'}: $e');
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
    final uri = buildUri('/posts/$id.json', {});
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
    final uri = buildUri('/tags.json', {'search[name_matches]': query, 'limit': '20'});
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
    final tagsList = (json['tag_string'] as String?)?.split(' ') ?? [];

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..tags = normalizeTags(tagsList.join(' '))
      ..author = (json['uploader']?['name'] as String?) ?? 'unknown'
      ..creatorId = resolveInt(json['uploader_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(file['size'])
      ..createdAt = resolveInt(json['created_at'])
      ..rating = json['rating'] as String? ?? 'q'
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['image_width']) ?? 0
      ..height = resolveInt(json['image_height']) ?? 0
      ..previewUrl = preview['url'] as String? ?? ''
      ..sampleUrl = largeFile['url'] as String? ?? file['url'] as String? ?? ''
      ..fileUrl = file['url'] as String? ?? ''
      ..fileExt = file['ext'] as String? ??
          _extFromUrl(file['url'] as String? ?? '')
      ..hasChildren = resolveBool(json['has_children']);
  }

  String _extFromUrl(String url) {
    final uri = Uri.parse(url);
    final ext = uri.pathSegments.last.split('.').lastOrNull;
    if (ext != null && ext.length <= 5) return ext;
    return 'jpg';
  }
}
