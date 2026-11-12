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
    final uri = Uri.parse('$_baseUrl/post.json')
        .replace(queryParameters: {'tags': 'parent:$parentId'});
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

      final List<dynamic> data = json.decode(resp.body);
      return data.map((item) => {
        'id': item['id'] as int? ?? 0,
        'tags': item['tags'] as String? ?? '',
        'created_at': item['created_at'] as int? ?? 0,
        'creator_id': item['creator_id'] as int? ?? 0,
        'author': item['author'] as String? ?? 'unknown',
        'source': item['source'] as String? ?? '',
        'score': item['score'] as int? ?? 0,
        'file_url': item['file_url'] as String? ?? '',
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
      }).toList();
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
}
