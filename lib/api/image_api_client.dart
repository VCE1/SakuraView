import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';

abstract class ImageApiClient {
  static final Logger _log = Logger('ApiClient');

  final ImageSite site;
  final String apiKey;
  final String username;

  ImageApiClient({
    required this.site,
    this.apiKey = '',
    this.username = '',
  });

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
      };

  Uri buildUri(String path, Map<String, String> queryParams) {
    final base = Uri.parse(site.apiBaseUrl);
    return base.replace(path: path, queryParameters: queryParams);
  }

  Future<http.Response> httpGet(Uri uri, {Map<String, String>? headers}) async {
    _log.info('--- httpGet ---');
    _log.info('site=${site.name}  url=${uri.toString()}');
    _log.info('headers=${headers ?? this.headers}');

    final client = await ProxyConfig.createClient();
    final sw = Stopwatch()..start();

    try {
      final response = await client.get(uri, headers: headers ?? this.headers);
      sw.stop();
      _log.info('=> HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');
      _log.fine('=> body length=${response.body.length}');
      return response;
    } catch (e, st) {
      sw.stop();
      _log.severe('=> FAIL after ${sw.elapsedMilliseconds}ms: $e\n$st');
      rethrow;
    } finally {
      client.close();
      _log.info('--- httpGet done ---');
    }
  }

  Future<List<PostHiveModel>> searchPosts({
    String? tags,
    int page = 1,
    int limit = 20,
    String? sort,
    bool safeMode = false,
  });

  Future<PostHiveModel?> getPostDetail(String id);

  Future<List<String>> searchTags(String query);

  Future<List<Map<String, dynamic>>> fetchChildPosts(int parentId) async {
    try {
      final posts = await searchPosts(tags: 'parent:$parentId', limit: 100);
      return posts.map((p) => p.toApiMap()).toList();
    } catch (e) {
      _log.warning('fetchChildPosts($parentId) on ${site.name} failed: $e');
      return [];
    }
  }

  Future<void> close() async {}

  @protected
  PostHiveModel parsePost(Map<String, dynamic> json);

  @protected
  String? resolveUrl(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  @protected
  String normalizeTags(String? rawTags) {
    if (rawTags == null || rawTags.isEmpty) return '';
    return rawTags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.replaceAll('_', ' ').trim())
        .join(' ');
  }

  @protected
  int? resolveInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @protected
  int? resolveTimestamp(dynamic value) {
    final asInt = resolveInt(value);
    if (asInt != null) return asInt;
    if (value is String && value.isNotEmpty) {
      final dt = DateTime.tryParse(value);
      if (dt != null) {
        return dt.millisecondsSinceEpoch ~/ 1000;
      }
    }
    return null;
  }

  @protected
  bool? resolveBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return null;
  }

  @protected
  int resolveScore(dynamic score) {
    if (score is Map<String, dynamic>) {
      return resolveInt(score['up']) ?? resolveInt(score['total']) ?? 0;
    }
    return resolveInt(score) ?? 0;
  }
}
