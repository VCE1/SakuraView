import 'package:flutter/material.dart';

/// 标准化后的图片内容分级。
///
/// 使用语义化编码（`safe` / `sensitive` / `questionable` / `explicit` / `unknown`），
/// 避免与 Danbooru (`s` = Sensitive) 和 Moebooru (`s` = Safe) 单字母缩写发生歧义。
enum ContentRating {
  safe('safe', '全年龄', 'Safe'),
  sensitive('sensitive', '敏感', 'Sensitive'),
  questionable('questionable', '存疑', 'Questionable'),
  explicit('explicit', '限制', 'Explicit'),
  unknown('unknown', '未知', 'Unknown');

  final String code;
  final String label;
  final String englishLabel;

  const ContentRating(this.code, this.label, this.englishLabel);

  bool get isSafe => this == ContentRating.safe;
  bool get isExplicit => this == ContentRating.explicit;
  bool get isUnknown => this == ContentRating.unknown;
  bool get isRestricted =>
      this == ContentRating.sensitive ||
      this == ContentRating.questionable ||
      this == ContentRating.explicit;

  /// 根据不同图源的原生字段规则，严格将原始分级解析为标准 [ContentRating]。
  ///
  /// - Danbooru / Gelbooru: `g`/`general` -> [safe], `s`/`sensitive` -> [sensitive], `q` -> [questionable], `e` -> [explicit]。
  /// - Moebooru (Yande.re / Konachan / Sakugabooru) / Rule34: `s`/`safe` -> [safe], `q` -> [questionable], `e` -> [explicit]。
  /// - E-Shuushuu: API 中 `rating` 为 1-10 星级评分而非安全分级，强制返回 [unknown]。
  /// - 缺失、空值或无法识别的值：强制返回 [unknown]，绝不默认归类为 [safe]。
  static ContentRating parse(
    Object? raw, {
    String? siteId,
  }) {
    final normalizedSite = (siteId ?? '').trim().toLowerCase();
    if (normalizedSite == 'eshuushuu' || normalizedSite == 'e-shuushuu') {
      // 若已保存标准语义编码（例如本地元数据迁移/编辑后），保留语义值；否则星级评分统一视作未知。
      final str = raw?.toString().trim().toLowerCase() ?? '';
      return _parseAlreadyCanonical(str) ?? ContentRating.unknown;
    }

    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) {
      return ContentRating.unknown;
    }

    // 优先匹配无歧义的多字符标准值
    final canonical = _parseAlreadyCanonical(value);
    if (canonical != null) {
      return canonical;
    }

    if (normalizedSite == 'zerochan') {
      if (value == 'safe' || value == 'all ages' || value == 'general') {
        return ContentRating.safe;
      }
      if (value == 'ecchi' || value == 'sensitive') {
        return ContentRating.sensitive;
      }
      if (value == 'questionable') {
        return ContentRating.questionable;
      }
      if (value == 'r18' || value == 'r-18' || value == 'explicit') {
        return ContentRating.explicit;
      }
      return ContentRating.unknown;
    }

    if (normalizedSite == 'danbooru' || normalizedSite == 'gelbooru') {
      switch (value) {
        case 'g':
        case 'general':
          return ContentRating.safe;
        case 's':
        case 'sensitive':
          return ContentRating.sensitive;
        case 'q':
        case 'questionable':
          return ContentRating.questionable;
        case 'e':
        case 'explicit':
          return ContentRating.explicit;
        case 'u':
        case 'unknown':
          return ContentRating.unknown;
        default:
          return ContentRating.unknown;
      }
    }

    // Moebooru / Rule34 以及传统缓存的单字符映射
    switch (value) {
      case 'g':
      case 'general':
      case 's':
      case 'safe':
        return ContentRating.safe;
      case 'q':
      case 'questionable':
        return ContentRating.questionable;
      case 'e':
      case 'explicit':
        return ContentRating.explicit;
      case 'u':
      case 'unknown':
        return ContentRating.unknown;
      default:
        return ContentRating.unknown;
    }
  }

  static ContentRating? _parseAlreadyCanonical(String value) {
    switch (value) {
      case 'safe':
        return ContentRating.safe;
      case 'sensitive':
        return ContentRating.sensitive;
      case 'questionable':
        return ContentRating.questionable;
      case 'explicit':
        return ContentRating.explicit;
      case 'unknown':
        return ContentRating.unknown;
      case 'general':
        return ContentRating.safe;
      default:
        return null;
    }
  }

  /// 为当前主题提供克制、低饱和的语义色，不采用高饱和刺眼霓虹色。
  Color resolveAccentColor(ColorScheme colorScheme) {
    switch (this) {
      case ContentRating.safe:
        return colorScheme.primary;
      case ContentRating.sensitive:
        return const Color(0xFFB7791F);
      case ContentRating.questionable:
        return const Color(0xFFC05621);
      case ContentRating.explicit:
        return colorScheme.error;
      case ContentRating.unknown:
        return colorScheme.outline;
    }
  }
}

/// 首页与搜索栏的内容分级筛选模式：全部 / 仅全年龄 / 仅 R18。
enum RatingFilterMode {
  all('all', 'ALL', '全部内容'),
  safe('safe', 'SAFE', '全年龄 SAFE'),
  r18('r18', 'R18', '仅 R18');

  final String code;
  final String shortLabel;
  final String displayLabel;

  const RatingFilterMode(this.code, this.shortLabel, this.displayLabel);

  bool get isAll => this == RatingFilterMode.all;
  bool get isSafe => this == RatingFilterMode.safe;
  bool get isR18Only => this == RatingFilterMode.r18;

  static RatingFilterMode fromName(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final mode in RatingFilterMode.values) {
      if (mode.name == normalized || mode.code == normalized) {
        return mode;
      }
    }
    return RatingFilterMode.safe;
  }

  /// 客户端兜底匹配标准化帖子（兼容未提供服务端 explicit 参数的图源）。
  bool matchesPost(Map<String, dynamic> post) {
    if (this == RatingFilterMode.all) return true;
    final site = (post['site'] ?? post['site_id'])?.toString();
    final rating = ContentRating.parse(post['rating'], siteId: site);
    if (this == RatingFilterMode.r18) {
      return rating.isExplicit;
    }
    // SAFE 模式放行安全/一般内容，拦截显式限制及存疑内容
    return !rating.isExplicit && rating != ContentRating.questionable;
  }
}

/// 作品来源链接、帖子链接与媒体类型规范化工具。
class SourceUrlResolver {
  SourceUrlResolver._();

  static final RegExp _pximgIdPattern = RegExp(
    r'https?://(?:[^/]+\.)?pximg\.net/.*?/(\d+)(?:_p\d+)?(?:\.[a-z0-9]+)?(?:\?.*)?$',
    caseSensitive: false,
  );

  static final RegExp _pixivLegacyPattern = RegExp(
    r'https?://(?:www\.)?pixiv\.net/(?:member_illust\.php\?[^#\s]*illust_id=|en/artworks/|artworks/)(\d+)',
    caseSensitive: false,
  );

  static final RegExp _urlSplitPattern = RegExp(r'\s+');

  /// 将原始 `source` 字符串规范化为可点击浏览的规范链接列表。
  ///
  /// 典型处理：
  /// - `https://i.pximg.net/img-original/img/.../152004614_p0.jpg` -> `https://www.pixiv.net/artworks/152004614`
  /// - `https://www.pixiv.net/member_illust.php?mode=medium&illust_id=123` -> `https://www.pixiv.net/artworks/123`
  /// - 自动拆分空格或换行分隔的多条来源 URL 并去重。
  static List<String> normalizeSourceUrls(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final results = <String>[];
    final seen = <String>{};
    for (final part in raw.trim().split(_urlSplitPattern)) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final normalized = normalizeSingleUrl(token);
      if (seen.add(normalized)) {
        results.add(normalized);
      }
    }
    return results;
  }

  /// 将单条来源文本/URL 规范化，尽量避免 Pixiv CDN 403 直链。
  static String normalizeSingleUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final pximgMatch = _pximgIdPattern.firstMatch(trimmed);
    if (pximgMatch != null) {
      final artworkId = pximgMatch.group(1);
      if (artworkId != null && artworkId.isNotEmpty) {
        return 'https://www.pixiv.net/artworks/$artworkId';
      }
    }

    final legacyMatch = _pixivLegacyPattern.firstMatch(trimmed);
    if (legacyMatch != null) {
      final artworkId = legacyMatch.group(1);
      if (artworkId != null && artworkId.isNotEmpty) {
        return 'https://www.pixiv.net/artworks/$artworkId';
      }
    }

    return trimmed;
  }

  /// 返回适合直接展示给用户的规范来源主文本。
  static String normalizeDisplaySource(String? raw) {
    final urls = normalizeSourceUrls(raw);
    if (urls.isNotEmpty) {
      return urls.first;
    }
    return raw?.trim() ?? '';
  }

  /// 构造帖子在对应图站的规范网页详情地址。
  static String canonicalPostUrl({
    required String siteId,
    required int postId,
    String? baseUrl,
  }) {
    if (postId <= 0) return '';
    final normalizedSite = siteId.trim().toLowerCase();
    final cleanBase = (baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');

    switch (normalizedSite) {
      case 'danbooru':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://danbooru.donmai.us'}/posts/$postId';
      case 'yandere':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://yande.re'}/post/show/$postId';
      case 'konachan':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://konachan.com'}/post/show/$postId';
      case 'sakugabooru':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://www.sakugabooru.com'}/post/show/$postId';
      case 'zerochan':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://www.zerochan.net'}/$postId';
      case 'gelbooru':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://gelbooru.com'}/index.php?page=post&s=view&id=$postId';
      case 'rule34':
        return 'https://rule34.xxx/index.php?page=post&s=view&id=$postId';
      case 'eshuushuu':
      case 'e-shuushuu':
        return '${cleanBase.isNotEmpty ? cleanBase : 'https://e-shuushuu.net'}/images/$postId';
      default:
        if (cleanBase.isEmpty) return '';
        return '$cleanBase/posts/$postId';
    }
  }

  static const Set<String> _videoExtensions = {
    'mp4',
    'webm',
    'mkv',
    'mov',
    'avi',
  };

  static const Set<String> _animatedImageExtensions = {
    'gif',
    'webp',
    'apng',
  };

  /// 判断 URL 或扩展名是否属于视频媒体（如 Sakugabooru / Danbooru 的 mp4/webm 帖子）。
  static bool isVideoMedia({String? url, String? fileExt}) {
    final ext = (fileExt ?? '').trim().toLowerCase().replaceAll('.', '');
    if (_videoExtensions.contains(ext)) {
      return true;
    }
    final rawUrl = (url ?? '').trim().toLowerCase();
    if (rawUrl.isEmpty) return false;
    final cleanPath = rawUrl.split('?').first;
    for (final vExt in _videoExtensions) {
      if (cleanPath.endsWith('.$vExt')) {
        return true;
      }
    }
    return false;
  }

  /// 判断 URL 或扩展名是否属于动图格式（GIF / WebP / APNG）。
  static bool isAnimatedMedia({String? url, String? fileExt}) {
    final ext = (fileExt ?? '').trim().toLowerCase().replaceAll('.', '');
    if (_animatedImageExtensions.contains(ext)) {
      return true;
    }
    final rawUrl = (url ?? '').trim().toLowerCase();
    if (rawUrl.isEmpty) return false;
    final cleanPath = rawUrl.split('?').first;
    for (final aExt in _animatedImageExtensions) {
      if (cleanPath.endsWith('.$aExt')) {
        return true;
      }
    }
    return false;
  }

  /// 确保相对 URL 或 `//` 协议相对 URL 补全为 HTTPS 绝对地址。
  static String ensureHttpsUrl(String? raw, {String? baseUrl}) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final cleanBase = (baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanBase.isEmpty) return trimmed;
    if (trimmed.startsWith('/')) {
      return '$cleanBase$trimmed';
    }
    return '$cleanBase/$trimmed';
  }

  /// 生成简洁规范的分享文本（不包含原出处链接）。
  static String formatShareText({
    required int postId,
    String canonicalPostUrl = '',
    String fallbackUrl = '',
    String? siteName,
  }) {
    final cleanSite = (siteName ?? '').trim();
    final header = cleanSite.isNotEmpty ? '$cleanSite #$postId' : 'POST #$postId';
    final cleanCanonical = canonicalPostUrl.trim();
    final cleanFallback = fallbackUrl.trim();
    final link = cleanCanonical.isNotEmpty ? cleanCanonical : cleanFallback;
    return link.isNotEmpty ? '$header\n$link' : header;
  }
}

/// 首页 / 搜索页图组折叠与跨页去重工具。
///
/// 解决父子图在接口按最新倒序返回（子图早于母图）或跨页加载时被拆分为多张卡片的问题。
class PostGroupHelper {
  PostGroupHelper._();

  static int extractId(Map<String, dynamic> post) {
    final raw = post['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static int? extractParentId(Map<String, dynamic> post) {
    final id = extractId(post);
    final raw = post['parent_id'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed <= 0 || parsed == id) {
      return null;
    }
    return parsed;
  }

  static int? extractPoolId(Map<String, dynamic> post) {
    final raw = post['pool_id'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static int? extractPixivId(Map<String, dynamic> post) {
    final raw = post['pixiv_id'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static bool hasGroup(Map<String, dynamic> post) {
    return post['has_children'] == true ||
        extractParentId(post) != null ||
        extractPoolId(post) != null ||
        (post['group_key']?.toString().isNotEmpty ?? false);
  }

  /// 返回同一个图组所属的规范分组键：
  /// - 属于画廊 / Pool 时返回 `'pool:<poolId>'`；
  /// - 存在有效 `parent_id` 时返回 `'parent:<parentId>'`；
  /// - 否则若 `has_children == true`，返回 `'parent:<id>'`；
  /// - 批次中命中同 `pixiv_id` 多页组时返回 `'pixiv:<pixivId>'`；
  /// - 独立作品返回 `null`。
  static String? resolveGroupKey(Map<String, dynamic> post) {
    final poolId = extractPoolId(post);
    if (poolId != null) {
      return 'pool:$poolId';
    }
    final parentId = extractParentId(post);
    if (parentId != null) {
      return 'parent:$parentId';
    }
    final explicit = post['group_key']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final id = extractId(post);
    if (post['has_children'] == true && id > 0) {
      return 'parent:$id';
    }
    return null;
  }

  static bool _isBetterGroupCover(
    Map<String, dynamic> candidate,
    Map<String, dynamic> currentBest,
    String groupKey,
  ) {
    if (groupKey.startsWith('pool:')) {
      final candOrder = (candidate['pool_index'] as num?)?.toInt();
      final bestOrder = (currentBest['pool_index'] as num?)?.toInt();
      if (candOrder != null && bestOrder != null && candOrder != bestOrder) {
        return candOrder < bestOrder;
      }
      if (candOrder != null && bestOrder == null) return true;
      return extractId(candidate) < extractId(currentBest);
    }
    if (groupKey.startsWith('parent:')) {
      final rootId = int.tryParse(groupKey.substring('parent:'.length)) ?? 0;
      return extractId(candidate) == rootId && extractId(currentBest) != rootId;
    }
    if (groupKey.startsWith('pixiv:')) {
      return extractId(candidate) < extractId(currentBest);
    }
    return false;
  }

  /// 将新拉取的 [incoming] 列表合并进已展示列表 [existing]，返回去重并完成图组合并后的新列表。
  static List<Map<String, dynamic>> mergeAndDeduplicate(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incoming,
  ) {
    final result = <Map<String, dynamic>>[
      for (final item in existing) Map<String, dynamic>.from(item),
    ];

    // 预统计同一 Pixiv 作品 ID 出现次数（用于识别 Danbooru 未建 Pool/parent 的多页 Pixiv 投稿）
    final pixivIdsSeenByPixiv = <int, Set<int>>{};
    void collectPixiv(Map<String, dynamic> m) {
      final id = extractId(m);
      final pixivId = extractPixivId(m);
      if (id > 0 && pixivId != null) {
        pixivIdsSeenByPixiv.putIfAbsent(pixivId, () => <int>{}).add(id);
      }
    }

    for (final item in result) {
      collectPixiv(item);
    }
    for (final item in incoming) {
      collectPixiv(item);
    }

    for (final item in result) {
      if (resolveGroupKey(item) == null) {
        final pixivId = extractPixivId(item);
        if (pixivId != null && (pixivIdsSeenByPixiv[pixivId]?.length ?? 0) >= 2) {
          item['group_key'] = 'pixiv:$pixivId';
          item['group_source'] = 'pixiv';
          item['has_children'] = true;
        }
      }
    }

    final normalizedIncoming = <Map<String, dynamic>>[
      for (final raw in incoming) Map<String, dynamic>.from(raw),
    ];
    for (final item in normalizedIncoming) {
      if (resolveGroupKey(item) == null) {
        final pixivId = extractPixivId(item);
        if (pixivId != null && (pixivIdsSeenByPixiv[pixivId]?.length ?? 0) >= 2) {
          item['group_key'] = 'pixiv:$pixivId';
          item['group_source'] = 'pixiv';
          item['has_children'] = true;
        }
      }
    }

    final seenIds = <int>{};
    final idToResultIndex = <int, int>{};
    final groupKeyToResultIndex = <String, int>{};

    for (var i = 0; i < result.length; i++) {
      final item = result[i];
      final id = extractId(item);
      if (id > 0) {
        seenIds.add(id);
        idToResultIndex[id] = i;
      }
      final gKey = resolveGroupKey(item);
      if (gKey != null) {
        groupKeyToResultIndex.putIfAbsent(gKey, () => i);
        if (item['has_children'] != true) {
          item['has_children'] = true;
        }
      }
    }

    // 预扫描本批新数据：同一图组优先挑选真正的父帖或画廊首图作为封面代表，
    // 确保即便子帖/后续页排在前面返回，最终也只渲染 1 张卡片。
    final bestRepByGroup = <String, Map<String, dynamic>>{};
    for (final raw in normalizedIncoming) {
      final id = extractId(raw);
      if (id > 0 && seenIds.contains(id)) continue;
      final gKey = resolveGroupKey(raw);
      if (gKey == null) continue;
      if (groupKeyToResultIndex.containsKey(gKey)) continue;
      if (gKey.startsWith('parent:')) {
        final rootId = int.tryParse(gKey.substring('parent:'.length)) ?? 0;
        if (rootId > 0 && idToResultIndex.containsKey(rootId)) continue;
      }

      final existingBest = bestRepByGroup[gKey];
      final isBetter =
          existingBest == null || _isBetterGroupCover(raw, existingBest, gKey);
      if (isBetter) {
        final copy = Map<String, dynamic>.from(raw);
        copy['has_children'] = true;
        bestRepByGroup[gKey] = copy;
      }
    }

    final emittedBatchGroups = <String>{};

    for (final raw in normalizedIncoming) {
      final id = extractId(raw);
      if (id > 0 && seenIds.contains(id)) {
        continue;
      }

      final gKey = resolveGroupKey(raw);
      if (gKey != null) {
        // 情况 A：前面批次已包含该图组卡片 -> 仅标记 ID 已见过与图组标识，不重复添加
        final existingGroupIdx = groupKeyToResultIndex[gKey];
        if (existingGroupIdx != null) {
          result[existingGroupIdx]['has_children'] = true;
          if (id > 0) seenIds.add(id);
          continue;
        }

        // 情况 B：前面批次曾以独立作品收录过母帖本身 -> 升级为图组卡片，不再新增子帖卡片
        if (gKey.startsWith('parent:')) {
          final rootId = int.tryParse(gKey.substring('parent:'.length)) ?? 0;
          final standaloneParentIdx =
              rootId > 0 ? idToResultIndex[rootId] : null;
          if (standaloneParentIdx != null) {
            result[standaloneParentIdx]['has_children'] = true;
            groupKeyToResultIndex[gKey] = standaloneParentIdx;
            if (id > 0) seenIds.add(id);
            continue;
          }
        }

        // 情况 C：本批首次遇到该图组 -> 放行本批选出的最优封面代表，其余同组兄弟/子帖折叠跳过
        if (!emittedBatchGroups.add(gKey)) {
          if (id > 0) seenIds.add(id);
          continue;
        }

        final rep = bestRepByGroup[gKey] ??
            (Map<String, dynamic>.from(raw)..['has_children'] = true);
        final repId = extractId(rep);
        if (repId > 0) {
          seenIds.add(repId);
          idToResultIndex[repId] = result.length;
        }
        if (id > 0) seenIds.add(id);
        groupKeyToResultIndex[gKey] = result.length;
        result.add(rep);
        continue;
      }

      final copy = Map<String, dynamic>.from(raw);
      if (id > 0) {
        seenIds.add(id);
        idToResultIndex[id] = result.length;
      }
      result.add(copy);
    }

    return result;
  }
}
