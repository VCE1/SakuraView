// lib/models/post_hive_model.dart
import 'package:hive/hive.dart';

part 'post_hive_model.g.dart';

@HiveType(typeId: 0)
class PostHiveModel extends HiveObject {
  @HiveField(0)
  late int id;

  @HiveField(1)
  String? tags;

  @HiveField(2)
  String? author;

  @HiveField(3)
  int? creatorId;

  @HiveField(4)
  String? source;

  @HiveField(5)
  int? fileSize;

  @HiveField(6)
  int? createdAt;

  @HiveField(7)
  String? rating;

  @HiveField(8)
  int? score;

  @HiveField(9)
  int? width;

  @HiveField(10)
  int? height;

  @HiveField(11)
  String? previewUrl;

  @HiveField(12)
  String? sampleUrl;

  @HiveField(13)
  String? fileUrl;

  @HiveField(14)
  String? fileExt;

  @HiveField(15)
  bool? hasChildren;

  @HiveField(16)
  String? localPath;

  @HiveField(17)
  int? parentId;

  @HiveField(18)
  String? siteName;

  @HiveField(19)
  String? uploader;

  @HiveField(20)
  List<String>? artistTags;

  @HiveField(21)
  List<String>? characterTags;

  @HiveField(22)
  List<String>? copyrightTags;

  @HiveField(23)
  List<String>? generalTags;

  @HiveField(24)
  List<String>? metaTags;

  @HiveField(25)
  int? previewWidth;

  @HiveField(26)
  int? previewHeight;

  @HiveField(27)
  int? poolId;

  @HiveField(28)
  String? poolName;

  @HiveField(29)
  int? pixivId;

  /// 运行期瞬态字段：记录当前帖子在画廊 Pool 中的页码序号，用于封面折叠排序。
  int? poolIndex;

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static List<String> _parseTagList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static PostHiveModel fromApiMap(Map<String, dynamic> map) {
    final artistList = _parseTagList(
      map['artist_tags'] ?? map['tag_string_artist'],
    );
    final characterList = _parseTagList(
      map['character_tags'] ?? map['tag_string_character'],
    );
    final copyrightList = _parseTagList(
      map['copyright_tags'] ?? map['tag_string_copyright'],
    );
    final generalList = _parseTagList(
      map['general_tags'] ?? map['tag_string_general'],
    );
    final metaList = _parseTagList(
      map['meta_tags'] ?? map['tag_string_meta'],
    );

    final uploaderVal =
        (map['uploader'] ?? map['uploader_name'])?.toString().trim();
    final authorVal = (map['author'] as String?)?.trim();
    final ratingRaw = map['rating']?.toString().trim();

    int? parsedCreatedAt;
    final rawCreated = map['created_at'];
    if (rawCreated is int) {
      parsedCreatedAt = rawCreated;
    } else if (rawCreated is String && rawCreated.isNotEmpty) {
      final asInt = int.tryParse(rawCreated);
      if (asInt != null) {
        parsedCreatedAt = asInt;
      } else {
        final dt = DateTime.tryParse(rawCreated);
        if (dt != null) {
          parsedCreatedAt = dt.millisecondsSinceEpoch ~/ 1000;
        }
      }
    }

    final mergedTags = (map['tags'] as String?)?.trim();
    final fallbackTags = mergedTags != null && mergedTags.isNotEmpty
        ? mergedTags
        : [
            ...copyrightList,
            ...characterList,
            ...artistList,
            ...generalList,
            ...metaList,
          ].join(' ');

    return PostHiveModel()
      ..id = _parseInt(map['id']) ?? 0
      ..tags = fallbackTags
      ..author = (authorVal != null && authorVal.isNotEmpty)
          ? authorVal
          : (artistList.isNotEmpty ? artistList.join(', ') : null)
      ..creatorId = _parseInt(map['creator_id'] ?? map['uploader_id'])
      ..source = map['source'] as String?
      ..fileSize = _parseInt(map['file_size'])
      ..createdAt = parsedCreatedAt
      ..rating = (ratingRaw != null && ratingRaw.isNotEmpty) ? ratingRaw : 'unknown'
      ..score = _parseInt(map['score'])
      ..width = _parseInt(map['width'])
      ..height = _parseInt(map['height'])
      ..previewUrl = (map['preview_url'] ?? map['thumbnail_url']) as String?
      ..sampleUrl = map['sample_url'] as String?
      ..fileUrl = (map['file_url'] ?? map['original_url']) as String?
      ..fileExt = map['file_ext'] as String?
      ..hasChildren = map['has_children'] as bool?
      ..parentId = _parseInt(map['parent_id'])
      ..siteName = (map['site'] ?? map['site_id'])?.toString()
      ..uploader = (uploaderVal != null && uploaderVal.isNotEmpty)
          ? uploaderVal
          : null
      ..artistTags = artistList.isEmpty ? null : artistList
      ..characterTags = characterList.isEmpty ? null : characterList
      ..copyrightTags = copyrightList.isEmpty ? null : copyrightList
      ..generalTags = generalList.isEmpty ? null : generalList
      ..metaTags = metaList.isEmpty ? null : metaList
      ..previewWidth = _parseInt(map['preview_width'] ?? map['actual_preview_width'])
      ..previewHeight = _parseInt(map['preview_height'] ?? map['actual_preview_height'])
      ..poolId = _parseInt(map['pool_id'])
      ..poolName = (map['pool_name'] as String?)?.trim()
      ..pixivId = _parseInt(map['pixiv_id']);
  }

  Map<String, dynamic> toApiMap({String? siteName}) {
    final effectiveSite = siteName ?? this.siteName;
    final artists = artistTags ?? const <String>[];
    final characters = characterTags ?? const <String>[];
    final copyrights = copyrightTags ?? const <String>[];
    final generals = generalTags ?? const <String>[];
    final metas = metaTags ?? const <String>[];

    return {
      'id': id,
      if (effectiveSite != null && effectiveSite.isNotEmpty)
        'site': effectiveSite,
      if (effectiveSite != null && effectiveSite.isNotEmpty)
        'site_id': effectiveSite,
      'tags': tags,
      'author': author,
      'uploader': uploader,
      'creator_id': creatorId,
      'source': source,
      'file_size': fileSize,
      'created_at': createdAt,
      'rating': rating,
      'score': score,
      'width': width,
      'height': height,
      if (previewWidth != null) 'preview_width': previewWidth,
      if (previewHeight != null) 'preview_height': previewHeight,
      'preview_url': previewUrl,
      'thumbnail_url': previewUrl,
      'sample_url': sampleUrl,
      'file_url': fileUrl,
      'original_url': fileUrl,
      'file_ext': fileExt,
      'has_children': hasChildren,
      'parent_id': parentId,
      if (poolId != null && poolId! > 0) 'pool_id': poolId,
      if (poolName != null && poolName!.isNotEmpty) 'pool_name': poolName,
      if (poolIndex != null) 'pool_index': poolIndex,
      if (pixivId != null && pixivId! > 0) 'pixiv_id': pixivId,
      'tag_string_artist': artists.join(' '),
      'tag_string_character': characters.join(' '),
      'tag_string_copyright': copyrights.join(' '),
      'tag_string_general': generals.join(' '),
      'tag_string_meta': metas.join(' '),
      'artist_tags': artists,
      'character_tags': characters,
      'copyright_tags': copyrights,
      'general_tags': generals,
      'meta_tags': metas,
      'local_path': localPath,
      'localPath': localPath,
      if (localPath != null) 'local_file_path': localPath,
    };
  }
}
