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
        'Accept': 'application/json',
        'User-Agent':
            'SakuraView - ${username.isNotEmpty ? username : "vce1"}',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  String _encodeTags(String tags) {
    if (tags.contains(',')) {
      return tags
          .split(',')
          .map((t) => t.trim().replaceAll('_', ' '))
          .where((t) => t.isNotEmpty)
          .join(',');
    }
    return tags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.replaceAll('_', ' '))
        .join(',');
  }

  /// Extracts valid JSON object from Zerochan response body even when Zerochan's
  /// server prepends an extra `{` and appends HTML `<p id="browse-filters"...`.
  static Map<String, dynamic>? extractZerochanJson(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through to tolerant extraction for Zerochan's malformed wrapper
    }

    final itemsKeyIdx = trimmed.indexOf('"items"');
    if (itemsKeyIdx != -1) {
      final startBrace = trimmed.lastIndexOf('{', itemsKeyIdx);
      if (startBrace != -1) {
        int depth = 0;
        bool inString = false;
        bool escaped = false;
        for (int i = startBrace; i < trimmed.length; i++) {
          final ch = trimmed.codeUnitAt(i);
          if (escaped) {
            escaped = false;
            continue;
          }
          if (ch == 0x5C /* \ */) {
            escaped = true;
            continue;
          }
          if (ch == 0x22 /* " */) {
            inString = !inString;
            continue;
          }
          if (!inString) {
            if (ch == 0x7B /* { */) {
              depth++;
            } else if (ch == 0x7D /* } */) {
              depth--;
              if (depth == 0) {
                final candidate = trimmed.substring(startBrace, i + 1);
                try {
                  final decoded = json.decode(candidate);
                  if (decoded is Map<String, dynamic>) return decoded;
                } catch (_) {}
                break;
              }
            }
          }
        }
      }
    }
    return null;
  }

  @override
  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
    bool safeMode = false,
  }) async {
    final base = Uri.parse(site.apiBaseUrl);
    final tagPath =
        tags != null && tags.trim().isNotEmpty ? '/${_encodeTags(tags.trim())}' : '/';
    final qParams = <String, String>{
      'json': '',
      'p': '$page',
      'l': '$limit',
      's': sort == 'fav' ? 'fav' : 'id',
    };
    final uri = base.replace(path: tagPath, queryParameters: qParams);
    _logger.info('Zerochan search: $uri');

    try {
      final response = await httpGet(uri);
      final data = extractZerochanJson(response.body);
      if (data == null) {
        if (response.statusCode != 200) {
          throw ApiException(
            'Zerochan returned ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        return [];
      }
      final List<dynamic> items = data['items'] as List<dynamic>? ?? [];
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
    } on ApiException {
      rethrow;
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
    final uri = base.replace(
      path: '/suggest',
      queryParameters: {'q': query, 'json': ''},
    );
    _logger.info('Zerochan tag search: $uri');

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return [];
      final List<dynamic> data = json.decode(response.body);
      return data
          .map((item) => item['value'] as String? ?? item['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      _logger.warning('Zerochan tag search failed: $e');
      return [];
    }
  }

  static String _toJpgThumb(String url) {
    if (url.endsWith('.avif') || url.endsWith('.webp')) {
      final dot = url.lastIndexOf('.');
      return '${url.substring(0, dot)}.jpg';
    }
    return url;
  }

  static String _deriveSampleFromThumb(String thumbUrl) {
    if (thumbUrl.isEmpty) return '';
    final jpgUrl = _toJpgThumb(thumbUrl);
    return jpgUrl
        .replaceFirst('://s3.zerochan.net/', '://s1.zerochan.net/')
        .replaceFirst('/240/', '/600/');
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final rawThumb = resolveUrl(json, ['thumb', 'thumbnail', 'medium', 'small']) ?? '';
    final preview = _toJpgThumb(rawThumb);
    final large = resolveUrl(json, ['large']) ?? _deriveSampleFromThumb(rawThumb);
    final full = resolveUrl(json, ['full', 'src']) ?? '';

    String resolvedTags = '';
    final rawTags = json['tags'];
    if (rawTags is List) {
      resolvedTags = rawTags
          .whereType<String>()
          .map((t) => t.trim().replaceAll(RegExp(r'\s+'), '_'))
          .where((t) => t.isNotEmpty)
          .join(' ');
    } else if (rawTags is String) {
      resolvedTags = normalizeTags(rawTags);
    }

    final primaryTag = (json['primary'] as String?) ?? (json['tag'] as String?) ?? '';
    final uploader = (json['uploader'] as String?) ??
        (json['user'] as String?) ??
        (primaryTag.isNotEmpty ? primaryTag : 'unknown');

    final resolvedSample = large.isNotEmpty ? large : (full.isNotEmpty ? full : preview);
    final resolvedFile = full.isNotEmpty ? full : resolvedSample;

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..tags = resolvedTags
      ..author = uploader
      ..creatorId = resolveInt(json['uploader_id']) ?? resolveInt(json['user_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size']) ?? resolveInt(json['size'])
      ..createdAt = resolveTimestamp(json['created']) ?? resolveTimestamp(json['created_at'])
      ..rating = (json['content'] as String? ?? 'Safe').toLowerCase().startsWith('safe')
          ? 's'
          : 'q'
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewUrl = preview.isNotEmpty ? preview : resolvedSample
      ..sampleUrl = resolvedSample
      ..fileUrl = resolvedFile
      ..fileExt = json['extension'] as String? ?? _extFromUrl(resolvedFile)
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
