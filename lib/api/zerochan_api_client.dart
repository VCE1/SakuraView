import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/api/image_api_client.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:logging/logging.dart';

class ZerochanApiClient extends ImageApiClient {
  ZerochanApiClient({super.apiKey, super.username})
      : super(site: ImageSite.zerochan);

  static final _logger = Logger('ZerochanApiClient');

  @override
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent':
            username.isNotEmpty ? 'vce1.sakuraview/1.0 ($username)' : 'vce1.sakuraview/1.0',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  String _encodeTags(String tags) {
    return tags.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).join(',');
  }

  @override
  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
  }) async {
    final base = Uri.parse(site.apiBaseUrl);
    final tagPath =
        tags != null && tags.isNotEmpty ? '/${_encodeTags(tags)}' : '/';
    final qParams = <String, String>{
      'json': '',
      'p': '$page',
      'l': '$limit',
      if (sort == 'fav') 's': 'fav',
    };
    final uri = base.replace(path: tagPath, queryParameters: qParams);
    _logger.info('Zerochan search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          'Zerochan returned ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final Map<String, dynamic> data = json.decode(response.body);
      final List<dynamic> items = data['items'] ?? [];
      final posts = <PostHiveModel>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final post = parsePost(item);
          if (post.id > 0) posts.add(post);
        } catch (e) {
          _logger.warning('Zerochan: failed to parse post id=${item['id'] ?? '?'}: $e');
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
    final base = Uri.parse(site.apiBaseUrl);
    final uri = base.replace(path: '/$id', queryParameters: {'json': ''});
    _logger.info('Zerochan post detail: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data is Map<String, dynamic>) {
        if (data.containsKey('id')) return parsePost(data);
        return null;
      }
      return null;
    } catch (e) {
      _logger.warning('Failed to get zerochan post detail: $e');
      return null;
    }
  }

  @override
  Future<List<String>> searchTags(String query) async {
    final base = Uri.parse(site.apiBaseUrl);
    final uri = base.replace(path: '/suggest', queryParameters: {'q': query});
    _logger.info('Zerochan tag search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return [];
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => item['name'] as String? ?? '').toList();
    } catch (e) {
      _logger.warning('Zerochan tag search failed: $e');
      return [];
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final full = json['full'] as String? ?? '';
    final thumbnail = json['thumb'] as String? ?? '';
    final src = json['src'] as String? ?? full;

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..tags = normalizeTags(json['tags'] as String?)
      ..author = json['uploader'] as String? ?? json['user'] as String? ?? 'unknown'
      ..creatorId = resolveInt(json['uploader_id']) ?? resolveInt(json['user_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size'])
      ..createdAt = resolveInt(json['created'])
      ..rating = (json['content'] as String? ?? 'Image').toLowerCase().startsWith('safe')
          ? 's'
          : 'q'
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewUrl = thumbnail.isEmpty ? full : thumbnail
      ..sampleUrl = full.isEmpty ? thumbnail : full
      ..fileUrl = src.isEmpty ? full : src
      ..fileExt = json['extension'] as String? ?? _extFromUrl(src.isNotEmpty ? src : full)
      ..hasChildren = resolveBool(json['has_children']);
  }

  String _extFromUrl(String url) {
    if (url.isEmpty) return 'jpg';
    final uri = Uri.parse(url);
    final ext = uri.pathSegments.last.split('.').lastOrNull;
    if (ext != null && ext.length <= 5) return ext;
    return 'jpg';
  }
}
