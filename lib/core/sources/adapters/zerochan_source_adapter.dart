import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

/// Zerochan JSON 适配器。
class ZerochanSourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('ZerochanSourceAdapter');

  const ZerochanSourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  @override
  Map<String, String> get headers {
    final map = <String, String>{
      'Accept': 'application/json',
      'User-Agent': userAgent.trim().isNotEmpty
          ? userAgent.trim()
          : 'SakuraView - ${username.isNotEmpty ? username : "vce1"}',
      'Referer': descriptor.effectiveReferer,
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    };
    if (cookies.trim().isNotEmpty) {
      map['Cookie'] = cookies.trim();
    }
    return map;
  }

  /// 从 Zerochan 服务端可能附带多余 HTML/括号的响应中容错提取 JSON 对象。
  static Map<String, dynamic>? extractZerochanJson(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

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
          if (ch == 0x5C) {
            escaped = true;
            continue;
          }
          if (ch == 0x22) {
            inString = !inString;
            continue;
          }
          if (!inString) {
            if (ch == 0x7B) {
              depth++;
            } else if (ch == 0x7D) {
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

  String _encodeTagsPath(String tags) {
    final parts = tags.contains(',')
        ? tags.split(',')
        : tags.split(RegExp(r'\s+'));
    return parts
        .map((t) => t.trim().replaceAll('_', ' '))
        .where((t) => t.isNotEmpty)
        .join(',');
  }

  @override
  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    final parsed = ImageSourceAdapter.extractUploaderFromQuery(query);
    final effectiveUploader = parsed.uploader;

    final tagTokens = <String>[];
    if (parsed.remainingTags.isNotEmpty) {
      tagTokens.add(parsed.remainingTags);
    }
    final artist = query.artist?.trim() ?? '';
    if (artist.isNotEmpty) {
      tagTokens.add(artist);
    }

    final merged = tagTokens.join(' ');
    final String path;
    if (effectiveUploader.isNotEmpty) {
      path = '/user/$effectiveUploader';
    } else if (merged.isNotEmpty) {
      path = '/${_encodeTagsPath(merged)}';
    } else {
      path = '/';
    }

    final uri = buildUri(path, <String, String>{
      'json': '',
      'p': '${query.page}',
      'l': '${query.limit}',
      's': query.sort == 'fav' ? 'fav' : 'id',
    });

    _logger.info('Zerochan search: $uri');

    try {
      final response = await httpGet(uri);
      final data = extractZerochanJson(response.body);
      if (data == null) {
        if (response.statusCode != 200) {
          throw ApiException(
            'Zerochan 请求失败 (HTTP ${response.statusCode})',
            statusCode: response.statusCode,
          );
        }
        return const [];
      }
      final items = data['items'] as List<dynamic>? ?? const [];
      final filterLower = tagTokens
          .expand((e) => e.split(RegExp(r'[\s,]+')))
          .map((e) => e.trim().toLowerCase().replaceAll(' ', '_'))
          .where((e) => e.isNotEmpty)
          .toList();
      final posts = <PostHiveModel>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final post = parsePost(item);
          if (post.id <= 0) continue;
          final effectiveRating = query.effectiveRatingFilter;
          if (!effectiveRating.matchesPost({
            'rating': post.rating,
            'site': descriptor.id,
          })) {
            continue;
          }
          if (effectiveUploader.isNotEmpty &&
              (post.uploader == null || post.uploader!.isEmpty)) {
            post.uploader = effectiveUploader;
          }
          // /user/<name>?json 不支持额外标签路径时，客户端兜底按剩余标签收敛结果。
          if (effectiveUploader.isNotEmpty && filterLower.isNotEmpty) {
            final postTagSet = (post.tags ?? '')
                .toLowerCase()
                .split(RegExp(r'\s+'))
                .where((e) => e.isNotEmpty)
                .toSet();
            final artistLower = (post.author ?? '').toLowerCase();
            final matchedAll = filterLower.every(
              (t) => postTagSet.contains(t) || artistLower.contains(t),
            );
            if (!matchedAll) continue;
          }
          posts.add(post);
        } catch (e) {
          _logger.warning('Zerochan parse failed: $e');
        }
      }
      return posts;
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } catch (e) {
      throw ApiException('Zerochan 加载失败: $e', originalError: e);
    }
  }

  @override
  Future<List<PostHiveModel>> fetchCloudFavorites({
    int page = 1,
    int limit = 40,
    bool safeMode = false,
    RatingFilterMode? ratingFilter,
  }) async {
    final targetUser = username.trim();
    if (targetUser.isEmpty && cookies.trim().isEmpty) {
      throw ApiException('请先在站点设置中配置 Zerochan 用户名或通过 WebView 登录以同步云端收藏');
    }
    final uri = buildUri('/', <String, String>{
      'json': '',
      'p': '$page',
      'l': '$limit',
      if (targetUser.isNotEmpty) 'fav': targetUser,
    });
    final response = await httpGet(uri);
    final data = extractZerochanJson(response.body);
    if (data == null) return const [];
    final items = data['items'] as List<dynamic>? ?? const [];
    final posts = <PostHiveModel>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final post = parsePost(item);
        if (post.id > 0) {
          final resolvedFilter = ratingFilter ??
              (safeMode ? RatingFilterMode.safe : RatingFilterMode.all);
          if (resolvedFilter.matchesPost({
            'rating': post.rating,
            'site': descriptor.id,
          })) {
            posts.add(post);
          }
        }
      } catch (_) {}
    }
    return posts;
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final jsonUri = buildUri('/$id', {'json': ''});
    final htmlUri = buildUri('/$id', const {});
    try {
      final jsonFuture = httpGet(jsonUri);
      final htmlFuture = httpGet(
        htmlUri,
        headers: {
          ...headers,
          'Accept': 'text/html,application/xhtml+xml',
        },
        timeout: const Duration(seconds: 10),
      ).then<http.Response?>((res) => res).catchError((_) => null);

      final jsonResponse = await jsonFuture;
      if (jsonResponse.statusCode != 200) return null;
      final data = extractZerochanJson(jsonResponse.body) ??
          json.decode(jsonResponse.body);
      if (data is! Map<String, dynamic> || !data.containsKey('id')) {
        return null;
      }
      final post = parsePost(data);
      final htmlResponse = await htmlFuture;
      if (htmlResponse != null && htmlResponse.statusCode == 200) {
        enrichPostFromHtml(post, htmlResponse.body);
      }
      return post;
    } catch (e) {
      _logger.warning('Failed to get Zerochan post detail: $e');
      return null;
    }
  }

  static final RegExp _ldJsonPattern = RegExp(
    r'<script[^>]*type=["\x27]application/ld\+json["\x27][^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  );
  static final RegExp _uploadedByDataUserPattern = RegExp(
    r'Uploaded\s+by[\s\S]{0,240}?data-user=["\x27]([^"\x27]+)["\x27]',
    caseSensitive: false,
  );
  static final RegExp _uploadedByHrefPattern = RegExp(
    r'Uploaded\s+by[\s\S]{0,240}?href=["\x27]/user/([^"\x27?#]+)["\x27]',
    caseSensitive: false,
  );
  static final RegExp _uploaderAvatarIdPattern = RegExp(
    r'Uploaded\s+by[\s\S]{0,300}?avatars\d*/(\d+)\.',
    caseSensitive: false,
  );
  static final RegExp _ulTagsBlockPattern = RegExp(
    r'<ul[^>]*id=["\x27]tags["\x27][^>]*>([\s\S]*?)</ul>',
    caseSensitive: false,
  );
  static final RegExp _liItemPattern = RegExp(
    r'<li\b([^>]*)>([\s\S]*?)</li>',
    caseSensitive: false,
  );
  static final RegExp _classAttrPattern = RegExp(
    r'class=["\x27]([^"\x27]+)["\x27]',
    caseSensitive: false,
  );
  static final RegExp _dataTagAttrPattern = RegExp(
    r'data-tag=["\x27]([^"\x27]+)["\x27]',
    caseSensitive: false,
  );
  static final RegExp _anchorTextPattern = RegExp(
    r'<a\b[^>]*>([\s\S]*?)</a>',
    caseSensitive: false,
  );

  /// 从 Zerochan 作品详情 HTML 中解析上传者、创作者画师、角色、作品来源与上传时间。
  static void enrichPostFromHtml(PostHiveModel post, String html) {
    if (html.isEmpty) return;

    // 1. 提取上传者用户名与上传者 ID（Uploaded by <a class="user" data-user="..."> + avatars/<id>）
    if (post.uploader == null || post.uploader!.isEmpty) {
      String? extractedUploader;
      final dataUserMatch = _uploadedByDataUserPattern.firstMatch(html);
      if (dataUserMatch != null) {
        extractedUploader = ImageSourceAdapter.decodeHtmlEntities(
          dataUserMatch.group(1) ?? '',
        ).trim();
      } else {
        final hrefMatch = _uploadedByHrefPattern.firstMatch(html);
        if (hrefMatch != null) {
          extractedUploader =
              Uri.decodeComponent(hrefMatch.group(1) ?? '').trim();
        }
      }
      if (extractedUploader != null && extractedUploader.isNotEmpty) {
        post.uploader = extractedUploader;
      }
    }

    if (post.creatorId == null || post.creatorId! <= 0) {
      final avatarMatch = _uploaderAvatarIdPattern.firstMatch(html);
      final parsedId = int.tryParse(avatarMatch?.group(1) ?? '');
      if (parsedId != null && parsedId > 0) {
        post.creatorId = parsedId;
      }
    }

    // 2. 从 <ul id="tags"> 还原画师（mangaka/studio）、角色、原作等标签分类
    final artistTags = <String>[...(post.artistTags ?? const <String>[])];
    final characterTags = <String>[...(post.characterTags ?? const <String>[])];
    final copyrightTags = <String>[...(post.copyrightTags ?? const <String>[])];
    final metaTags = <String>[...(post.metaTags ?? const <String>[])];
    final knownCategorizedLower = <String>{
      ...artistTags.map((e) => e.toLowerCase()),
      ...characterTags.map((e) => e.toLowerCase()),
      ...copyrightTags.map((e) => e.toLowerCase()),
      ...metaTags.map((e) => e.toLowerCase()),
    };

    void addUniqueTag(List<String> target, String rawTag) {
      final normalized = ImageSourceAdapter.normalizeTagToken(rawTag);
      if (normalized.isEmpty) return;
      final lower = normalized.toLowerCase();
      if (target.any((e) => e.toLowerCase() == lower)) return;
      target.add(normalized);
      knownCategorizedLower.add(lower);
    }

    final ulMatch = _ulTagsBlockPattern.firstMatch(html);
    if (ulMatch != null) {
      final ulBody = ulMatch.group(1) ?? '';
      for (final liMatch in _liItemPattern.allMatches(ulBody)) {
        final attrs = liMatch.group(1) ?? '';
        final innerHtml = liMatch.group(2) ?? '';
        final classMatch = _classAttrPattern.firstMatch(attrs);
        if (classMatch == null) continue;
        final classes = classMatch
            .group(1)!
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((c) => c.isNotEmpty)
            .toSet();

        final tagMatch = _dataTagAttrPattern.firstMatch(attrs) ??
            _dataTagAttrPattern.firstMatch(innerHtml);
        String rawTag = '';
        if (tagMatch != null) {
          rawTag = ImageSourceAdapter.decodeHtmlEntities(
            tagMatch.group(1) ?? '',
          );
        } else {
          final aMatch = _anchorTextPattern.firstMatch(innerHtml);
          if (aMatch != null) {
            rawTag = ImageSourceAdapter.decodeHtmlEntities(
              aMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ''),
            );
          }
        }
        if (rawTag.trim().isEmpty) continue;

        if (classes.contains('mangaka') ||
            classes.contains('artist') ||
            classes.contains('studio') ||
            classes.contains('circle')) {
          addUniqueTag(artistTags, rawTag);
        } else if (classes.contains('character')) {
          addUniqueTag(characterTags, rawTag);
        } else if (classes.contains('game') ||
            classes.contains('series') ||
            classes.contains('anime') ||
            classes.contains('manga') ||
            classes.contains('visual') ||
            classes.contains('novel') ||
            classes.contains('light') ||
            classes.contains('movie') ||
            classes.contains('ova') ||
            classes.contains('book') ||
            classes.contains('franchise') ||
            classes.contains('copyright')) {
          addUniqueTag(copyrightTags, rawTag);
        } else if (classes.contains('source') || classes.contains('meta')) {
          addUniqueTag(metaTags, rawTag);
        }
      }
    }

    // 3. 解析 JSON-LD 作为画师名与发布时间的可靠补充
    for (final ldMatch in _ldJsonPattern.allMatches(html)) {
      final rawJson = (ldMatch.group(1) ?? '').trim();
      if (rawJson.isEmpty) continue;
      try {
        final decoded = json.decode(rawJson);
        if (decoded is! Map<String, dynamic>) continue;
        final ldAuthor = decoded['author'];
        if (ldAuthor is Map<String, dynamic>) {
          final name = ldAuthor['name']?.toString() ?? '';
          if (name.trim().isNotEmpty) {
            addUniqueTag(artistTags, name);
          }
        } else if (ldAuthor is List) {
          for (final entry in ldAuthor) {
            if (entry is Map<String, dynamic>) {
              final name = entry['name']?.toString() ?? '';
              if (name.trim().isNotEmpty) {
                addUniqueTag(artistTags, name);
              }
            }
          }
        }
        if (post.createdAt == null) {
          final dateStr = decoded['datePublished']?.toString() ?? '';
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) {
            post.createdAt = dt.millisecondsSinceEpoch ~/ 1000;
          }
        }
      } catch (_) {}
    }

    if (artistTags.isNotEmpty) {
      post.artistTags = artistTags;
      // 与其他适配器保持一致：author 仅填写真实画师，绝不混入 uploader
      post.author = artistTags.join(', ');
    }
    if (characterTags.isNotEmpty) post.characterTags = characterTags;
    if (copyrightTags.isNotEmpty) post.copyrightTags = copyrightTags;
    if (metaTags.isNotEmpty) post.metaTags = metaTags;

    // 保留其余未归类标签到 generalTags，并确保总标签字符串完整
    final existingTokens = (post.tags ?? '')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final existingLower = existingTokens.map((e) => e.toLowerCase()).toSet();
    for (final tag in [
      ...artistTags,
      ...characterTags,
      ...copyrightTags,
      ...metaTags,
    ]) {
      if (existingLower.add(tag.toLowerCase())) {
        existingTokens.add(tag);
      }
    }
    post.tags = existingTokens.join(' ');
    final remainingGeneral = existingTokens
        .where((e) => !knownCategorizedLower.contains(e.toLowerCase()))
        .toList();
    post.generalTags = remainingGeneral.isEmpty ? null : remainingGeneral;
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final clean = query.trim().replaceAll('_', ' ');
    if (clean.isEmpty) return const [];
    final uri = buildUri('/suggest', {'q': clean, 'json': ''});
    try {
      final response = await httpGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final value = (item['value'] as String? ??
                    item['name'] as String? ??
                    '')
                .trim();
            return TagSuggestion(
              value: value.replaceAll(' ', '_'),
              label: value,
              category: 'general',
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
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
    final rawThumb =
        resolveUrl(json, ['thumb', 'thumbnail', 'medium', 'small']) ?? '';
    final preview = _toJpgThumb(rawThumb);
    final large = resolveUrl(json, ['large']) ?? _deriveSampleFromThumb(rawThumb);
    String full = resolveUrl(json, ['full', 'src']) ?? '';

    String resolvedTags = '';
    final List<String> tagTokens = [];
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.trim().isNotEmpty) {
          tagTokens.add(t.trim().replaceAll(RegExp(r'\s+'), '_'));
        }
      }
      resolvedTags = tagTokens.join(' ');
    } else if (rawTags is String) {
      resolvedTags = normalizeTags(rawTags);
      tagTokens.addAll(splitSpaceTags(resolvedTags));
    }

    final primaryTag =
        (json['primary'] as String?) ?? (json['tag'] as String?) ?? '';
    final uploader =
        ((json['uploader'] as String?) ?? (json['user'] as String?) ?? '')
            .trim();
    final id = resolveInt(json['id']) ?? 0;

    if (full.isEmpty && primaryTag.isNotEmpty && id > 0) {
      final cleanTag = primaryTag.replaceAll(' ', '.');
      full =
          'https://static.zerochan.net/${Uri.encodeComponent(cleanTag)}.full.$id.jpg';
    }

    final resolvedSample =
        large.isNotEmpty ? large : (full.isNotEmpty ? full : preview);
    final resolvedFile = full.isNotEmpty ? full : resolvedSample;

    return PostHiveModel()
      ..id = id
      ..siteName = descriptor.id
      ..tags = resolvedTags
      ..generalTags = tagTokens.isEmpty ? null : tagTokens
      ..author = null
      ..uploader = uploader.isNotEmpty ? uploader : null
      ..creatorId = resolveInt(json['uploader_id']) ?? resolveInt(json['user_id'])
      ..source = json['source'] as String? ?? ''
      ..fileSize = resolveInt(json['file_size']) ?? resolveInt(json['size'])
      ..createdAt = resolveTimestamp(json['created']) ??
          resolveTimestamp(json['created_at'])
      // Zerochan 未提供安全分级时必须严格保持 unknown，绝不默以为 safe
      ..rating = descriptor.normalizeRating(json['content']).code
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewUrl = preview.isNotEmpty ? preview : resolvedSample
      ..sampleUrl = resolvedSample
      ..fileUrl = resolvedFile
      ..fileExt = json['extension'] as String? ?? extFromUrl(resolvedFile)
      ..hasChildren = resolveBool(json['has_children']);
  }
}
