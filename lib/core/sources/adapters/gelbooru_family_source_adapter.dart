import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

/// Gelbooru DAPI 协议族适配器（统一支持 Gelbooru / Safebooru / Rule34 DAPI 与 HTML 详情补充）。
class GelbooruFamilySourceAdapter extends ImageSourceAdapter {
  static final _logger = Logger('GelbooruFamilySourceAdapter');

  const GelbooruFamilySourceAdapter({
    required super.descriptor,
    super.credentials,
  });

  bool get _isXmlOnly => descriptor.engine == SourceEngineType.gelbooruXml;
  bool get _isGelbooru => descriptor.id == 'gelbooru';
  bool get _isRule34 => descriptor.id == 'rule34';

  Map<String, String> _withAuth(Map<String, String> params) {
    final effectiveUserId =
        userId.trim().isNotEmpty ? userId.trim() : username.trim();
    if (effectiveUserId.isNotEmpty && apiKey.trim().isNotEmpty) {
      return {
        ...params,
        'user_id': effectiveUserId,
        'api_key': apiKey.trim(),
      };
    }
    return params;
  }

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    final tagTokens = <String>[];
    if (query.tags.trim().isNotEmpty) {
      tagTokens.addAll(
        query.tags
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty),
      );
    }

    final uploader = query.uploader?.trim() ?? '';
    if (uploader.isNotEmpty &&
        !tagTokens.any((t) => t.toLowerCase().startsWith('user:'))) {
      tagTokens.add('user:${uploader.replaceAll(' ', '_')}');
    }

    final artist = query.artist?.trim() ?? '';
    if (artist.isNotEmpty) {
      final cleanArtist = artist.replaceAll(' ', '_');
      if (!tagTokens.contains(cleanArtist)) {
        tagTokens.add(cleanArtist);
      }
    }

    final sort = query.sort?.trim() ?? '';
    if (sort.isNotEmpty &&
        !tagTokens.any((t) => t.toLowerCase().startsWith('sort:'))) {
      tagTokens.add(sort);
    }

    if (!tagTokens.any((t) => t.contains('rating:'))) {
      switch (query.effectiveRatingFilter) {
        case RatingFilterMode.safe:
          tagTokens.add(_isGelbooru ? 'rating:general' : 'rating:s');
          break;
        case RatingFilterMode.r18:
          tagTokens.add(_isGelbooru ? 'rating:explicit' : 'rating:e');
          break;
        case RatingFilterMode.all:
          break;
      }
    }

    final effectiveTags = tagTokens.join(' ');
    final params = _withAuth(<String, String>{
      'page': 'dapi',
      's': 'post',
      'q': 'index',
      'limit': '${query.limit}',
      'pid': '${query.page > 0 ? query.page - 1 : 0}',
      if (!_isXmlOnly) 'json': '1',
      if (effectiveTags.isNotEmpty) 'tags': effectiveTags,
    });

    final uri = buildUri('/index.php', params);
    _logger.info('[${descriptor.id}] DAPI search: $uri');

    try {
      final response = await httpGet(uri);
      _validateResponseOrThrow(response);

      if (_isXmlOnly) {
        return parseXmlPostsPayload(response.body);
      }
      return parseJsonPostsPayload(response.body);
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('网络请求失败: ${e.message}', originalError: e);
    } on FormatException catch (e) {
      throw ApiException('${descriptor.name} 返回数据格式异常', originalError: e);
    } catch (e) {
      throw ApiException('${descriptor.name} 加载失败: $e', originalError: e);
    }
  }

  void _validateResponseOrThrow(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        '${descriptor.name} 接口鉴权失败 (HTTP ${response.statusCode})，请在「图源管理」或「站点账号」中配置正确的 User ID 与 API Key。',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        '${descriptor.name} 请求失败 (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    final trimmed = response.body.trim();
    if (_isRule34 &&
        trimmed.toLowerCase().contains('missing authentication')) {
      throw ApiException(
        'Rule34 API 当前要求身份认证：请在「图源管理 -> ${descriptor.name}」配置 User ID 与 API Key。',
        statusCode: 401,
      );
    }
  }

  /// 解析 Gelbooru (`{"post": [...]}`) 或 Rule34 (`[...]`) JSON 响应。
  List<PostHiveModel> parseJsonPostsPayload(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const [];
    final dynamic decoded = json.decode(trimmed);
    final List<dynamic> items;

    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final rawPost = decoded['post'];
      if (rawPost is List) {
        items = rawPost;
      } else if (rawPost is Map<String, dynamic>) {
        items = [rawPost];
      } else {
        return const [];
      }
    } else {
      return const [];
    }

    final posts = <PostHiveModel>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final post = parsePost(item);
        if (post.id > 0) posts.add(post);
      } catch (e) {
        _logger.warning(
          '[${descriptor.id}] failed to parse JSON post: $e',
        );
      }
    }
    return posts;
  }

  /// 解析 Gelbooru XML DAPI 响应（用于兼容仅输出 XML 的站点扩展）。
  List<PostHiveModel> parseXmlPostsPayload(String xmlBody) {
    final trimmed = xmlBody.trim();
    if (trimmed.isEmpty) return const [];
    final doc = XmlDocument.parse(trimmed);
    final posts = <PostHiveModel>[];
    for (final node in doc.findAllElements('post')) {
      final attrs = <String, dynamic>{};
      for (final attr in node.attributes) {
        attrs[attr.name.local] = attr.value;
      }
      // 某些 XML 变体将字段作为子元素而非属性返回
      if (!attrs.containsKey('id')) {
        for (final child in node.childElements) {
          attrs[child.name.local] = child.innerText;
        }
      }
      try {
        final post = parsePost(attrs);
        if (post.id > 0) posts.add(post);
      } catch (e) {
        _logger.warning('[${descriptor.id}] failed to parse XML post: $e');
      }
    }
    return posts;
  }

  @override
  Future<PostHiveModel?> getPostDetail(String id) async {
    final params = _withAuth(<String, String>{
      'page': 'dapi',
      's': 'post',
      'q': 'index',
      'id': id,
      if (!_isXmlOnly) 'json': '1',
    });
    final uri = buildUri('/index.php', params);

    try {
      final response = await httpGet(uri);
      _validateResponseOrThrow(response);
      final list = _isXmlOnly
          ? parseXmlPostsPayload(response.body)
          : parseJsonPostsPayload(response.body);
      if (list.isEmpty) return null;
      final post = list.first;

      // 详情页按需调用 s=tag&q=index 为扁平标签补充画师 / 角色 / 原作分类，确保不混淆上传者。
      await _enrichTagCategories(post);
      return post;
    } catch (e) {
      _logger.warning('[${descriptor.id}] getPostDetail($id) failed: $e');
      return null;
    }
  }

  Future<void> _enrichTagCategories(PostHiveModel post) async {
    final tokens = splitSpaceTags(post.tags);
    if (tokens.isEmpty) return;

    final typeMap = <String, int>{};
    // 仅 Gelbooru 主站及纯 XML 扩展按 `names=` 批量查询；Safebooru/Rule34 直接回退 s=view 解析避免多余请求
    if (_isGelbooru || _isXmlOnly) {
      for (int i = 0; i < tokens.length && i < 80; i += 40) {
        final chunk = tokens.sublist(i, (i + 40).clamp(0, tokens.length));
        try {
          final uri = buildUri(
            '/index.php',
            _withAuth({
              'page': 'dapi',
              's': 'tag',
              'q': 'index',
              if (_isGelbooru) 'json': '1',
              'names': chunk.join(' '),
            }),
          );
          final response =
              await httpGet(uri, timeout: const Duration(seconds: 6));
          if (response.statusCode != 200) continue;
          final bodyTrimmed = response.body.trimLeft();
          if (bodyTrimmed.startsWith('<')) {
            final doc = XmlDocument.parse(bodyTrimmed);
            for (final tagEl in doc.findAllElements('tag')) {
              final name = tagEl.getAttribute('name') ?? '';
              final type = int.tryParse(tagEl.getAttribute('type') ?? '') ?? 0;
              if (name.isNotEmpty) typeMap[name.toLowerCase()] = type;
            }
          } else if (bodyTrimmed.isNotEmpty) {
            final decoded = json.decode(bodyTrimmed);
            final List<dynamic> tagList = decoded is Map<String, dynamic>
                ? (decoded['tag'] as List<dynamic>? ?? const [])
                : (decoded is List ? decoded : const []);
            for (final item in tagList) {
              if (item is Map<String, dynamic>) {
                final name = item['name']?.toString() ?? '';
                final type = resolveInt(item['type']) ?? 0;
                if (name.isNotEmpty) typeMap[name.toLowerCase()] = type;
              }
            }
          }
        } catch (_) {}
      }
    }

    if (typeMap.isNotEmpty) {
      final artists = <String>[];
      final characters = <String>[];
      final copyrights = <String>[];
      final metas = <String>[];
      final generals = <String>[];

      for (final tag in tokens) {
        switch (typeMap[tag.toLowerCase()]) {
          case 1:
            artists.add(tag);
            break;
          case 3:
            copyrights.add(tag);
            break;
          case 4:
            characters.add(tag);
            break;
          case 5:
            metas.add(tag);
            break;
          default:
            generals.add(tag);
            break;
        }
      }

      post.artistTags = artists.isEmpty ? null : artists;
      post.characterTags = characters.isEmpty ? null : characters;
      post.copyrightTags = copyrights.isEmpty ? null : copyrights;
      post.metaTags = metas.isEmpty ? null : metas;
      post.generalTags = generals.isEmpty ? null : generals;
      if (artists.isNotEmpty) {
        post.author = artists.join(', ');
      }
    }

    // Rule34 / Safebooru 等站点的 DAPI 列表常缺少 owner 或标签分类：回退抓取 s=view HTML。
    final missingUploader = post.uploader == null || post.uploader!.trim().isEmpty;
    final missingCategories = (post.artistTags?.isEmpty ?? true) &&
        (post.characterTags?.isEmpty ?? true) &&
        (post.copyrightTags?.isEmpty ?? true) &&
        (post.metaTags?.isEmpty ?? true);

    if ((missingUploader || missingCategories) && post.id > 0) {
      try {
        var htmlUri = buildUri('/index.php', {
          'page': 'post',
          's': 'view',
          'id': '${post.id}',
        });
        // api.rule34.xxx 为纯 API 域名，详情 HTML 位于主域名 rule34.xxx。
        if (htmlUri.host.startsWith('api.')) {
          htmlUri = htmlUri.replace(host: htmlUri.host.substring(4));
        }
        final response = await httpGet(
          htmlUri,
          headers: {
            ...headers,
            'Accept': 'text/html,application/xhtml+xml',
          },
          timeout: const Duration(seconds: 8),
        );
        if (response.statusCode == 200) {
          enrichPostFromViewHtml(post, response.body);
        }
      } catch (_) {}
    }
  }

  static final RegExp _postedByPattern = RegExp(
    r'(?:<li>|\b)(?:Posted|Uploaded)\s*:[\s\S]{0,200}?\bby\s*<a\b[^>]*>([\s\S]*?)</a>',
    caseSensitive: false,
  );
  static final RegExp _tagSidebarItemPattern = RegExp(
    r'<li\b[^>]*class=["\x27][^"\x27]*tag-type-(artist|copyright|character|metadata|meta|general)[^"\x27]*["\x27][^>]*>([\s\S]*?)</li>',
    caseSensitive: false,
  );
  static final RegExp _htmlAnchorPattern = RegExp(
    r'<a\b([^>]*)>([\s\S]*?)</a>',
    caseSensitive: false,
  );
  static final RegExp _hrefTagsParamPattern = RegExp(
    r'[?&]tags=([^&\s"\x27]+)',
    caseSensitive: false,
  );

  /// 从 Gelbooru / Rule34 / Safebooru 的 `s=view` HTML 中补充上传者与标签分类。
  static void enrichPostFromViewHtml(PostHiveModel post, String html) {
    if (html.isEmpty) return;

    // 1. 解析 Posted: ... by <a ...>uploader</a>，仅写入 uploader，绝不混淆 author
    if (post.uploader == null || post.uploader!.trim().isEmpty) {
      final byMatch = _postedByPattern.firstMatch(html);
      if (byMatch != null) {
        final rawUser = (byMatch.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '');
        final uploader = ImageSourceAdapter.decodeHtmlEntities(rawUser).trim();
        if (uploader.isNotEmpty) {
          post.uploader = uploader;
        }
      }
    }

    // 2. 解析侧边栏标签分类，注意跳过 Safebooru 等站点的 `?` wiki 链接
    final artists = <String>[...(post.artistTags ?? const <String>[])];
    final characters = <String>[...(post.characterTags ?? const <String>[])];
    final copyrights = <String>[...(post.copyrightTags ?? const <String>[])];
    final metas = <String>[...(post.metaTags ?? const <String>[])];
    final categorizedLower = <String>{
      ...artists.map((e) => e.toLowerCase()),
      ...characters.map((e) => e.toLowerCase()),
      ...copyrights.map((e) => e.toLowerCase()),
      ...metas.map((e) => e.toLowerCase()),
    };

    void addTag(List<String> list, String token) {
      final normalized = ImageSourceAdapter.normalizeTagToken(token);
      if (normalized.isEmpty) return;
      final lower = normalized.toLowerCase();
      if (list.any((e) => e.toLowerCase() == lower)) return;
      list.add(normalized);
      categorizedLower.add(lower);
    }

    final parsedGenerals = <String>[];
    var foundSidebar = false;

    for (final itemMatch in _tagSidebarItemPattern.allMatches(html)) {
      foundSidebar = true;
      final kind = (itemMatch.group(1) ?? '').toLowerCase();
      final body = itemMatch.group(2) ?? '';
      String resolvedTag = '';

      for (final anchor in _htmlAnchorPattern.allMatches(body)) {
        final attrs = anchor.group(1) ?? '';
        final hrefLower = attrs.toLowerCase();
        if (hrefLower.contains('page=wiki')) continue;
        final text = ImageSourceAdapter.decodeHtmlEntities(
          (anchor.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
        ).trim();
        if (text == '?' || text == '+' || text == '-') continue;

        final tagsParam = _hrefTagsParamPattern.firstMatch(attrs);
        if (tagsParam != null) {
          try {
            resolvedTag = ImageSourceAdapter.decodeHtmlEntities(
              Uri.decodeQueryComponent(tagsParam.group(1)!),
            ).trim();
          } catch (_) {}
        }
        if (resolvedTag.isEmpty && text.isNotEmpty) {
          resolvedTag = text;
        }
        if (resolvedTag.isNotEmpty) break;
      }

      if (resolvedTag.isEmpty) continue;
      switch (kind) {
        case 'artist':
          addTag(artists, resolvedTag);
          break;
        case 'character':
          addTag(characters, resolvedTag);
          break;
        case 'copyright':
          addTag(copyrights, resolvedTag);
          break;
        case 'metadata':
        case 'meta':
          addTag(metas, resolvedTag);
          break;
        case 'general':
          final normalized = ImageSourceAdapter.normalizeTagToken(resolvedTag);
          if (normalized.isNotEmpty) parsedGenerals.add(normalized);
          break;
      }
    }

    if (!foundSidebar) return;

    if (artists.isNotEmpty) {
      post.artistTags = artists;
      post.author = artists.join(', ');
    }
    if (characters.isNotEmpty) post.characterTags = characters;
    if (copyrights.isNotEmpty) post.copyrightTags = copyrights;
    if (metas.isNotEmpty) post.metaTags = metas;

    final existingTokens = (post.tags ?? '')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final combinedGenerals = <String>[];
    final seenGeneralLower = <String>{};
    for (final t in [...existingTokens, ...parsedGenerals]) {
      final lower = t.toLowerCase();
      if (!categorizedLower.contains(lower) && seenGeneralLower.add(lower)) {
        combinedGenerals.add(t);
      }
    }
    post.generalTags = combinedGenerals.isEmpty ? null : combinedGenerals;
  }

  @override
  Future<List<TagSuggestion>> suggestTags(String query) async {
    final clean = query.trim().replaceAll(' ', '_');
    if (clean.isEmpty) return const [];

    try {
      final Uri uri;
      if (_isGelbooru) {
        uri = buildUri('/index.php', {
          'page': 'autocomplete2',
          'term': clean,
          'type': 'tag_query',
          'limit': '20',
        });
      } else {
        uri = buildUri('/autocomplete.php', {'q': clean});
      }

      final response = await httpGet(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final value = item['value']?.toString() ?? '';
            final label = item['label']?.toString() ?? value;
            final categoryRaw =
                (item['category']?.toString() ?? 'tag').toLowerCase();
            final category = switch (categoryRaw) {
              'artist' => 'artist',
              'copyright' => 'copyright',
              'character' => 'character',
              'metadata' || 'meta' => 'meta',
              _ => 'general',
            };
            var count = resolveInt(item['post_count']);
            if (count == null) {
              final countMatch = RegExp(r'\((\d+)\)\s*$').firstMatch(label);
              if (countMatch != null) {
                count = int.tryParse(countMatch.group(1)!);
              }
            }
            return TagSuggestion(
              value: value,
              label: label,
              category: category,
              postCount: count,
            );
          })
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (e) {
      _logger.fine('[${descriptor.id}] autocomplete failed: $e');
      return const [];
    }
  }

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) {
    final rawTags = (json['tags'] as String? ?? '').trim();
    final uploaderName = (json['owner'] as String? ?? '').trim();

    final rawFile = resolveUrl(json, ['file_url']) ?? '';
    final rawSample = resolveUrl(json, ['sample_url']) ?? '';
    final rawPreview = resolveUrl(json, ['preview_url']) ?? '';

    final effectivePreview =
        rawPreview.isNotEmpty ? rawPreview : (rawSample.isNotEmpty ? rawSample : rawFile);
    final effectiveSample =
        rawSample.isNotEmpty ? rawSample : (rawFile.isNotEmpty ? rawFile : effectivePreview);
    final effectiveFile =
        rawFile.isNotEmpty ? rawFile : effectiveSample;

    return PostHiveModel()
      ..id = resolveInt(json['id']) ?? 0
      ..siteName = descriptor.id
      ..tags = rawTags
      ..author = null // DAPI 列表接口不含标签分类，不将上传者 owner 冒充画师
      ..uploader = uploaderName.isNotEmpty ? uploaderName : null
      ..creatorId = resolveInt(json['creator_id'])
      ..generalTags = splitSpaceTags(rawTags)
      ..source = json['source'] as String? ?? ''
      ..createdAt = _parseFlexibleTimestamp(json['created_at']) ??
          resolveTimestamp(json['change'])
      ..rating = descriptor.normalizeRating(json['rating']).code
      ..score = resolveScore(json['score'])
      ..width = resolveInt(json['width']) ?? 0
      ..height = resolveInt(json['height']) ?? 0
      ..previewWidth = resolveInt(json['preview_width'])
      ..previewHeight = resolveInt(json['preview_height'])
      ..previewUrl = effectivePreview
      ..sampleUrl = effectiveSample
      ..fileUrl = effectiveFile
      ..fileExt = extFromUrl(effectiveFile, fallback: 'jpg')
      ..hasChildren = resolveBool(json['has_children']) ?? false
      ..parentId = resolveInt(json['parent_id']);
  }

  static final RegExp _booruDatePattern = RegExp(
    r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})\s+(\d{4})$',
  );

  static const Map<String, int> _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  int? _parseFlexibleTimestamp(dynamic raw) {
    final standard = resolveTimestamp(raw);
    if (standard != null) return standard;
    if (raw is! String) return null;
    final m = _booruDatePattern.firstMatch(raw.trim());
    if (m == null) return null;
    final month = _months[m.group(1)];
    if (month == null) return null;
    final day = int.parse(m.group(2)!);
    final hour = int.parse(m.group(3)!);
    final minute = int.parse(m.group(4)!);
    final second = int.parse(m.group(5)!);
    final tzStr = m.group(6)!;
    final year = int.parse(m.group(7)!);

    final tzSign = tzStr.startsWith('-') ? -1 : 1;
    final tzHours = int.parse(tzStr.substring(1, 3));
    final tzMinutes = int.parse(tzStr.substring(3, 5));
    final offset = Duration(
      minutes: tzSign * (tzHours * 60 + tzMinutes),
    );
    final utcDt = DateTime.utc(year, month, day, hour, minute, second)
        .subtract(offset);
    return utcDt.millisecondsSinceEpoch ~/ 1000;
  }
}
