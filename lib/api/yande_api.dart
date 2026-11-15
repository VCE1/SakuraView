import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';

class YandeApi {
  static final Logger _log = Logger('YandeApi');
  static const String _baseUrl = 'https://yande.re';

  static Future<List<Map<String, dynamic>>> fetchChildPosts(int parentId) async {
    final uri = Uri.parse('$_baseUrl/post.json').replace(
      queryParameters: {
        'tags': 'parent:$parentId',
        'api_version': '2',
        'include_tags': '1',
      },
    );
    _log.info('fetchChildPosts($parentId) GET $uri');

    final client = await ProxyConfig.createClient();
    final sw = Stopwatch()..start();
    try {
      final resp = await client.get(uri);
      sw.stop();
      _log.info('=> HTTP ${resp.statusCode} in ${sw.elapsedMilliseconds}ms');

      if (resp.statusCode != 200) {
        _log.severe('=> failed: ${resp.statusCode} ${resp.body}');
        throw ApiException('Failed to load child posts',
            statusCode: resp.statusCode);
      }

      return parseChildPostsPayload(json.decode(resp.body));
    } on SocketException catch (e) {
      sw.stop();
      _log.severe('=> SOCKET ERROR after ${sw.elapsedMilliseconds}ms: $e');
      throw ApiException(
          'Connection failed. Check proxy/network.', originalError: e);
    } on http.ClientException catch (e) {
      // ignore: avoid_catching_errors
      sw.stop();
      _log.severe('=> HTTP CLIENT ERROR after ${sw.elapsedMilliseconds}ms: $e');
      throw ApiException('Network error: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      sw.stop();
      _log.severe('=> JSON PARSE ERROR: $e');
      throw ApiException('Invalid response format.', originalError: e);
    } catch (e, st) {
      sw.stop();
      _log.severe('=> UNKNOWN ERROR after ${sw.elapsedMilliseconds}ms: $e\n$st');
      throw ApiException('Request failed.', originalError: e);
    } finally {
      client.close();
      _log.info('fetchChildPosts($parentId) done');
    }
  }

  /// 解析 Moebooru `api_version=2&include_tags=1` 子帖数据，严格拆分上传者与画师标签。
  static List<Map<String, dynamic>> parseChildPostsPayload(dynamic decoded) {
    final List<dynamic> rawPosts;
    final Map<String, String> tagTypes = {};

    if (decoded is Map<String, dynamic>) {
      rawPosts = decoded['posts'] as List<dynamic>? ?? const [];
      final rawTags = decoded['tags'];
      if (rawTags is Map) {
        for (final entry in rawTags.entries) {
          tagTypes[entry.key.toString()] = entry.value.toString();
        }
      }
    } else if (decoded is List) {
      rawPosts = decoded;
    } else {
      return const [];
    }

    return rawPosts.whereType<Map<String, dynamic>>().map((item) {
      final tagsStr = (item['tags'] as String? ?? '').trim();
      final tokens = tagsStr
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      final artistTags = <String>[];
      final characterTags = <String>[];
      final copyrightTags = <String>[];
      final generalTags = <String>[];
      final metaTags = <String>[];

      for (final token in tokens) {
        switch (tagTypes[token]) {
          case 'artist':
          case 'circle':
            artistTags.add(token);
            break;
          case 'character':
            characterTags.add(token);
            break;
          case 'copyright':
            copyrightTags.add(token);
            break;
          case 'faults':
          case 'meta':
            metaTags.add(token);
            break;
          default:
            generalTags.add(token);
            break;
        }
      }

      // Moebooru 的 item['author'] 字段固定是上传者用户名
      final uploader = (item['author'] as String? ?? '').trim();

      return <String, dynamic>{
        'id': item['id'] as int? ?? 0,
        'site': 'yandere',
        'site_id': 'yandere',
        'tags': tagsStr,
        'created_at': item['created_at'] as int? ?? 0,
        'creator_id': item['creator_id'] as int? ?? 0,
        'uploader': uploader,
        'author': artistTags.join(', '),
        if (artistTags.isNotEmpty) 'artist_tags': artistTags,
        if (characterTags.isNotEmpty) 'character_tags': characterTags,
        if (copyrightTags.isNotEmpty) 'copyright_tags': copyrightTags,
        if (generalTags.isNotEmpty) 'general_tags': generalTags,
        if (metaTags.isNotEmpty) 'meta_tags': metaTags,
        'source': item['source'] as String? ?? '',
        'score': item['score'] as int? ?? 0,
        'file_url': item['file_url'] as String? ?? '',
        'file_size': item['file_size'] as int?,
        'file_ext': item['file_ext'] as String?,
        'preview_url': item['preview_url'] as String? ?? '',
        'preview_width': item['preview_width'] as int? ?? 0,
        'preview_height': item['preview_height'] as int? ?? 0,
        'sample_url': item['sample_url'] as String? ?? '',
        'jpeg_url': item['jpeg_url'] as String? ?? '',
        'rating': item['rating'] as String? ?? 's',
        'has_children': item['has_children'] as bool? ?? false,
        'parent_id': item['parent_id'] as int?,
        'width': item['width'] as int? ?? 0,
        'height': item['height'] as int? ?? 0,
      };
    }).toList();
  }
}
