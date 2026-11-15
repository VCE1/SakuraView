import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/site_config.dart';

/// Unified, type-safe domain model representing an artwork/post across all Booru sites.
/// Strictly supports 3 image resolution tiers:
/// 1. [thumbnailUrl]: Low-res thumbnail for fast grid/waterfall rendering.
/// 2. [sampleUrl]: Medium-resolution compressed sample for fast viewer display.
/// 3. [originalUrl]: Full-resolution master original file (for high-res viewing/download).
class Post {
  final int id;
  final ImageSite site;
  final String siteId;
  final String thumbnailUrl;
  final String sampleUrl;
  final String originalUrl;
  final int width;
  final int height;
  final int previewWidth;
  final int previewHeight;
  final int? fileSize;
  final String fileExt;
  final String rating; // 'safe', 'sensitive', 'questionable', 'explicit', 'unknown'
  final int score;
  final int? favCount;
  final String author;
  final String uploader;
  final int? creatorId;
  final String source;
  final String postUrl;
  final DateTime? createdAt;
  final bool hasChildren;
  final int? parentId;
  final int? poolId;
  final String poolName;
  final int? pixivId;

  // Granular tag categories
  final List<String> artistTags;
  final List<String> characterTags;
  final List<String> copyrightTags;
  final List<String> generalTags;
  final List<String> metaTags;

  // Local storage path if downloaded
  final String? localPath;
  final bool isLocalFile;

  const Post({
    required this.id,
    this.site = ImageSite.danbooru,
    String? siteId,
    required this.thumbnailUrl,
    required this.sampleUrl,
    required this.originalUrl,
    required this.width,
    required this.height,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.fileSize,
    this.fileExt = 'jpg',
    this.rating = 'unknown',
    this.score = 0,
    this.favCount,
    this.author = '',
    this.uploader = '',
    this.creatorId,
    this.source = '',
    this.postUrl = '',
    this.createdAt,
    this.hasChildren = false,
    this.parentId,
    this.poolId,
    this.poolName = '',
    this.pixivId,
    this.artistTags = const [],
    this.characterTags = const [],
    this.copyrightTags = const [],
    this.generalTags = const [],
    this.metaTags = const [],
    this.localPath,
    this.isLocalFile = false,
  }) : siteId = siteId ?? '';

  String get effectiveSiteId => siteId.isNotEmpty ? siteId : site.name;

  ContentRating get contentRating =>
      ContentRating.parse(rating, siteId: effectiveSiteId);

  List<String> get normalizedSources =>
      SourceUrlResolver.normalizeSourceUrls(source);

  String get resolvedPostUrl => postUrl.isNotEmpty
      ? postUrl
      : SourceUrlResolver.canonicalPostUrl(
          siteId: effectiveSiteId,
          postId: id,
        );

  bool get isVideo =>
      SourceUrlResolver.isVideoMedia(url: originalUrl, fileExt: fileExt) ||
      SourceUrlResolver.isVideoMedia(url: sampleUrl) ||
      (localPath != null &&
          SourceUrlResolver.isVideoMedia(url: localPath));

  bool get isAnimatedImage =>
      SourceUrlResolver.isAnimatedMedia(url: originalUrl, fileExt: fileExt) ||
      SourceUrlResolver.isAnimatedMedia(url: sampleUrl) ||
      (localPath != null &&
          SourceUrlResolver.isAnimatedMedia(url: localPath));

  /// 返回最适合内嵌播放的远端视频地址（兼容 Danbooru zip 动图附带 webm/mp4 样本的场景）。
  String get preferredVideoUrl {
    if (SourceUrlResolver.isVideoMedia(url: originalUrl)) {
      return originalUrl;
    }
    if (SourceUrlResolver.isVideoMedia(url: sampleUrl)) {
      return sampleUrl;
    }
    return originalUrl.isNotEmpty ? originalUrl : sampleUrl;
  }

  String get primaryArtist {
    if (artistTags.isNotEmpty) return artistTags.join(', ');
    return author;
  }

  /// All tags combined as a single list.
  List<String> get allTags {
    final list = <String>[];
    list.addAll(copyrightTags);
    list.addAll(characterTags);
    list.addAll(artistTags);
    list.addAll(generalTags);
    list.addAll(metaTags);
    return list;
  }

  /// All tags formatted as a space-separated string.
  String get tagsString => allTags.join(' ');

  double get aspectRatio {
    if (width > 0 && height > 0) {
      return (width / height).clamp(0.4, 2.5);
    }
    if (previewWidth > 0 && previewHeight > 0) {
      return (previewWidth / previewHeight).clamp(0.4, 2.5);
    }
    return 1.0;
  }

  /// Unique Hero transition tag ensuring 100% collision-free fluid transitions.
  String get heroTag => 'post_hero_${effectiveSiteId}_$id';

  Post copyWith({
    String? siteId,
    String? originalUrl,
    String? sampleUrl,
    String? thumbnailUrl,
    int? previewWidth,
    int? previewHeight,
    int? fileSize,
    String? fileExt,
    String? rating,
    String? author,
    String? uploader,
    String? source,
    String? postUrl,
    bool? hasChildren,
    int? parentId,
    int? poolId,
    String? poolName,
    int? pixivId,
    List<String>? artistTags,
    List<String>? characterTags,
    List<String>? copyrightTags,
    List<String>? generalTags,
    List<String>? metaTags,
    String? localPath,
    bool? isLocalFile,
  }) {
    return Post(
      id: id,
      site: site,
      siteId: siteId ?? effectiveSiteId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      sampleUrl: sampleUrl ?? this.sampleUrl,
      originalUrl: originalUrl ?? this.originalUrl,
      width: width,
      height: height,
      previewWidth: previewWidth ?? this.previewWidth,
      previewHeight: previewHeight ?? this.previewHeight,
      fileSize: fileSize ?? this.fileSize,
      fileExt: fileExt ?? this.fileExt,
      rating: rating ?? this.rating,
      score: score,
      favCount: favCount,
      author: author ?? this.author,
      uploader: uploader ?? this.uploader,
      creatorId: creatorId,
      source: source ?? this.source,
      postUrl: postUrl ?? this.postUrl,
      createdAt: createdAt,
      hasChildren: hasChildren ?? this.hasChildren,
      parentId: parentId ?? this.parentId,
      poolId: poolId ?? this.poolId,
      poolName: poolName ?? this.poolName,
      pixivId: pixivId ?? this.pixivId,
      artistTags: artistTags ?? this.artistTags,
      characterTags: characterTags ?? this.characterTags,
      copyrightTags: copyrightTags ?? this.copyrightTags,
      generalTags: generalTags ?? this.generalTags,
      metaTags: metaTags ?? this.metaTags,
      localPath: localPath ?? this.localPath,
      isLocalFile: isLocalFile ?? this.isLocalFile,
    );
  }

  /// Serialize to Map for persistence or interop.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'site': effectiveSiteId,
      'site_id': effectiveSiteId,
      'thumbnail_url': thumbnailUrl,
      'preview_url': thumbnailUrl,
      'sample_url': sampleUrl,
      'file_url': originalUrl,
      'original_url': originalUrl,
      'width': width,
      'height': height,
      if (previewWidth > 0) 'preview_width': previewWidth,
      if (previewHeight > 0) 'preview_height': previewHeight,
      'file_size': fileSize,
      'file_ext': fileExt,
      'rating': contentRating.code,
      'score': score,
      'fav_count': favCount,
      'author': primaryArtist,
      'uploader': uploader,
      'creator_id': creatorId,
      'source': source,
      'post_url': resolvedPostUrl,
      'created_at': createdAt != null ? createdAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'has_children': hasChildren,
      'parent_id': parentId,
      if (poolId != null && poolId! > 0) 'pool_id': poolId,
      if (poolName.isNotEmpty) 'pool_name': poolName,
      if (pixivId != null && pixivId! > 0) 'pixiv_id': pixivId,
      'tags': tagsString,
      'tag_string_artist': artistTags.join(' '),
      'tag_string_character': characterTags.join(' '),
      'tag_string_copyright': copyrightTags.join(' '),
      'tag_string_general': generalTags.join(' '),
      'tag_string_meta': metaTags.join(' '),
      'artist_tags': artistTags,
      'character_tags': characterTags,
      'copyright_tags': copyrightTags,
      'general_tags': generalTags,
      'meta_tags': metaTags,
      'local_file_path': localPath,
      'localPath': localPath,
      'is_local_file': isLocalFile,
    };
  }

  factory Post.fromMap(Map<String, dynamic> map) {
    final siteStr = (map['site_id'] ?? map['site'] ?? '').toString().trim();
    ImageSite site = ImageSite.danbooru;
    for (final s in ImageSite.values) {
      if (s.name.toLowerCase() == siteStr.toLowerCase()) {
        site = s;
        break;
      }
    }
    final resolvedSiteId = siteStr.isNotEmpty ? siteStr : site.name;

    final rawTags = map['tags'] as String? ?? '';
    final allTokens = rawTags
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    List<String> parseCategory(String listKey, String stringKey) {
      final listVal = map[listKey];
      if (listVal is List && listVal.isNotEmpty) {
        return listVal
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final str = map[stringKey] as String? ?? '';
      if (str.trim().isEmpty) return [];
      return str.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }

    final artist = parseCategory('artist_tags', 'tag_string_artist');
    final character = parseCategory('character_tags', 'tag_string_character');
    final copyright = parseCategory('copyright_tags', 'tag_string_copyright');
    final general = parseCategory('general_tags', 'tag_string_general');
    final meta = parseCategory('meta_tags', 'tag_string_meta');

    // Fallback if no specific categorized tags exist at all
    final generalFinal = general.isNotEmpty
        ? general
        : (artist.isEmpty &&
                character.isEmpty &&
                copyright.isEmpty &&
                meta.isEmpty
            ? allTokens
            : const <String>[]);

    DateTime? parsedDate;
    final rawCreated = map['created_at'];
    if (rawCreated is int && rawCreated > 0) {
      parsedDate = rawCreated > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawCreated)
          : DateTime.fromMillisecondsSinceEpoch(rawCreated * 1000);
    } else if (rawCreated is String && rawCreated.isNotEmpty) {
      final asInt = int.tryParse(rawCreated);
      if (asInt != null && asInt > 0) {
        parsedDate = asInt > 100000000000
            ? DateTime.fromMillisecondsSinceEpoch(asInt)
            : DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
      } else {
        parsedDate = DateTime.tryParse(rawCreated);
      }
    }

    final normalizedRating = ContentRating.parse(
      map['rating'],
      siteId: resolvedSiteId,
    ).code;

    return Post(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}') ?? 0,
      site: site,
      siteId: resolvedSiteId,
      thumbnailUrl: (map['thumbnail_url'] ?? map['preview_url'] ?? map['sample_url'] ?? '') as String,
      sampleUrl: (map['sample_url'] ?? map['preview_url'] ?? map['file_url'] ?? '') as String,
      originalUrl: (map['original_url'] ?? map['file_url'] ?? map['sample_url'] ?? '') as String,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      previewWidth: (map['preview_width'] as num?)?.toInt() ?? 0,
      previewHeight: (map['preview_height'] as num?)?.toInt() ?? 0,
      fileSize: (map['file_size'] as num?)?.toInt(),
      fileExt: map['file_ext'] as String? ?? 'jpg',
      rating: normalizedRating,
      score: (map['score'] as num?)?.toInt() ?? 0,
      favCount: (map['fav_count'] as num?)?.toInt(),
      author: (map['author'] as String? ?? '').trim(),
      uploader: (map['uploader'] as String? ?? '').trim(),
      creatorId: (map['creator_id'] as num?)?.toInt(),
      source: map['source'] as String? ?? '',
      postUrl: map['post_url'] as String? ?? '',
      createdAt: parsedDate,
      hasChildren: map['has_children'] as bool? ?? false,
      parentId: (map['parent_id'] as num?)?.toInt(),
      poolId: (map['pool_id'] as num?)?.toInt(),
      poolName: (map['pool_name'] as String? ?? '').trim(),
      pixivId: (map['pixiv_id'] as num?)?.toInt(),
      artistTags: artist,
      characterTags: character,
      copyrightTags: copyright,
      generalTags: generalFinal,
      metaTags: meta,
      localPath: (map['local_file_path'] ?? map['localPath'] ?? map['local_path']) as String?,
      isLocalFile: map['is_local_file'] as bool? ?? false,
    );
  }
}
