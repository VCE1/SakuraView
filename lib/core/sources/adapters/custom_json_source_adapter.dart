import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

/// 声明式自定义 JSON 图源适配器（读取用户导入 JSON 中的路径与字段映射规则）。
class CustomJsonSourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('CustomJsonSourceAdapter');

  const CustomJsonSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  Map<String, dynamic> get _cfg => descriptor.customConfig ?? const {};
  Map<String, dynamic> get _fieldMap {
    final raw = _cfg['fieldMap'];
    if (raw is Map<String, dynamic>) return raw;
    return const {};
  }

  String _cfgStr(String key, String fallback) {
    final v = _cfg[key]?.toString().trim() ?? '';
    return v.isNotEmpty ? v : fallback;
  }

  String _mapKey(String canonical, String fallback) {
    final v = _fieldMap[canonical]?.toString().trim() ?? '';
    return v.isNotEmpty ? v : fallback;
  }

  dynamic _readNested(Map<String, dynamic> json, String path) {
    if (path.isEmpty) return null;
    dynamic current = json;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    final searchPath = _cfgStr('searchPath', '/post.json');
    final tagsParam = _cfgStr('tagsParam', 'tags');
    final pageParam = _cfgStr('pageParam', 'page');
    final limitParam = _cfgStr('limitParam', 'limit');
    final safeTag = _cfgStr('safeModeTag', '');
    final r18Tag = _cfgStr('r18ModeTag', '');

    final tagTokens = <String>[];
    if (query.tags.trim().isNotEmpty) tagTokens.add(query.tags.trim());
    if ((query.uploader ?? '').trim().isNotEmpty &&
        descriptor.capabilities.supportsUploaderFilter) {
      tagTokens.add('user:${query.uploader!.trim().replaceAll(' ', '_')}');
    }
    if ((query.artist ?? '').trim().isNotEmpty) {
      tagTokens.add(query.artist!.trim().replaceAll(' ', '_'));
    }
    switch (query.effectiveRatingFilter) {
      case RatingFilterMode.safe:
        if (safeTag.isNotEmpty) tagTokens.add(safeTag);
        break;
      case RatingFilterMode.r18:
        if (r18Tag.isNotEmpty) tagTokens.add(r18Tag);
        break;
      case RatingFilterMode.all:
        break;
    }

    final mergedTags = tagTokens.join(' ');
    final uri = buildUri(searchPath, {
      pageParam: '${query.page}',
      limitParam: '${query.limit}',
      if (mergedTags.isNotEmpty) tagsParam: mergedTags,
    });

    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) {
        throw ApiException(
          '${descriptor.name} 请求失败 (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      final dynamic decoded = json.decode(response.body);
      final itemsPath = _cfg['itemsPath']?.toString().trim() ?? '';
      final dynamic rawItems = (itemsPath.isNotEmpty && decoded is Map<String, dynamic>)
          ? _readNested(decoded, itemsPath)
          : (decoded is Map<String, dynamic>
              ? (decoded['posts'] ?? decoded['items'] ?? decoded['data'] ?? decoded['post'])
              : decoded);

      if (rawItems is! List) return const [];
      final posts = <PostHiveModel>[];
      for (final item in rawItems) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final p = parsePost(item);
          if (p.id > 0) posts.add(p);
        } catch (_) {}
      }
      return posts;
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } catch (e) {
      throw ApiException('${descriptor.name} 加载失败: $e', originalError: e);
    }
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final detailPath = _cfg['detailPath']?.toString().trim() ?? '';
    if (detailPath.isEmpty) return null;
    final resolvedPath = detailPath.contains('{id}')
        ? detailPath.replaceAll('{id}', id)
        : detailPath;
    final uri = buildUri(
      resolvedPath,
      detailPath.contains('{id}') ? null : {'tags': 'id:$id', 'limit': '1'},
    );
    try {
      final response = await httpGet(uri);
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        return parsePost(decoded.first as Map<String, dynamic>);
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded['posts'] is List && (decoded['posts'] as List).isNotEmpty) {
          return parsePost((decoded['posts'] as List).first as Map<String, dynamic>);
        }
        return parsePost(decoded);
      }
    } catch (e) {
      _logger.fine('[${descriptor.id}] detail failed: $e');
    }
    return null;
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final autocompletePath = _cfg['autocompletePath']?.toString().trim() ?? '';
    final clean = query.trim();
    if (autocompletePath.isEmpty || clean.isEmpty) return const [];
    final param = _cfgStr('autocompleteParam', 'q');
    final uri = buildUri(autocompletePath, {param: clean, 'limit': '20'});
    try {
      final response = await httpGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final name = (item['value'] ?? item['name'] ?? '').toString().trim();
            return TagSuggestion(
              value: name,
              label: (item['label'] ?? name).toString(),
              postCount: resolveInt(item['count'] ?? item['post_count']),
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final preview = ensureHttps(
      _readNested(json, _mapKey('previewUrl', 'preview_url'))?.toString(),
    );
    final sample = ensureHttps(
      _readNested(json, _mapKey('sampleUrl', 'sample_url'))?.toString(),
    );
    final file = ensureHttps(
      _readNested(json, _mapKey('fileUrl', 'file_url'))?.toString(),
    );
    final rawTags =
        _readNested(json, _mapKey('tags', 'tags'))?.toString().trim() ?? '';
    final uploader =
        _readNested(json, _mapKey('uploader', 'uploader'))?.toString().trim() ??
            '';
    final artist =
        _readNested(json, _mapKey('artist', 'artist'))?.toString().trim() ?? '';

    final effectivePreview =
        preview.isNotEmpty ? preview : (sample.isNotEmpty ? sample : file);
    final effectiveSample =
        sample.isNotEmpty ? sample : (file.isNotEmpty ? file : effectivePreview);
    final effectiveFile = file.isNotEmpty ? file : effectiveSample;

    return PostHiveModel()
      ..id = resolveInt(_readNested(json, _mapKey('id', 'id'))) ?? 0
      ..siteName = descriptor.id
      ..tags = rawTags
      ..author = artist.isNotEmpty ? artist : null
      ..uploader = uploader.isNotEmpty ? uploader : null
      ..artistTags = artist.isNotEmpty ? [artist] : null
      ..generalTags = splitSpaceTags(rawTags)
      ..source =
          _readNested(json, _mapKey('source', 'source'))?.toString() ?? ''
      ..createdAt =
          resolveTimestamp(_readNested(json, _mapKey('createdAt', 'created_at')))
      ..rating = descriptor
          .normalizeRating(_readNested(json, _mapKey('rating', 'rating')))
          .code
      ..score =
          resolveScore(_readNested(json, _mapKey('score', 'score')))
      ..width =
          resolveInt(_readNested(json, _mapKey('width', 'width'))) ?? 0
      ..height =
          resolveInt(_readNested(json, _mapKey('height', 'height'))) ?? 0
      ..previewUrl = effectivePreview
      ..sampleUrl = effectiveSample
      ..fileUrl = effectiveFile
      ..fileExt = extFromUrl(effectiveFile, fallback: 'jpg')
      ..hasChildren =
          resolveBool(_readNested(json, _mapKey('hasChildren', 'has_children')))
      ..parentId =
          resolveInt(_readNested(json, _mapKey('parentId', 'parent_id')));
  }
}
