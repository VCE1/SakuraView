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

  // =======================================================
  // == 在这里添加 localPath 字段 ==
  // =======================================================
  @HiveField(16)
  String? localPath;
  // =======================================================

  static PostHiveModel fromApiMap(Map<String, dynamic> map) {
    return PostHiveModel()
      ..id = map['id'] as int
      ..tags = map['tags'] as String?
      ..author = map['author'] as String?
      ..creatorId = map['creator_id'] as int?
      ..source = map['source'] as String?
      ..fileSize = map['file_size'] as int?
      ..createdAt = map['created_at'] as int?
      ..rating = map['rating'] as String?
      ..score = map['score'] as int?
      ..width = map['width'] as int?
      ..height = map['height'] as int?
      ..previewUrl = map['preview_url'] as String?
      ..sampleUrl = map['sample_url'] as String?
      ..fileUrl = map['file_url'] as String?
      ..fileExt = map['file_ext'] as String?
      ..hasChildren = map['has_children'] as bool?;
    // 注意：localPath 是在下载完成后单独赋值的，所以这里不需要
  }

  Map<String, dynamic> toApiMap() {
    return {
      'id': id,
      'tags': tags,
      'author': author,
      'creator_id': creatorId,
      'source': source,
      'file_size': fileSize,
      'created_at': createdAt,
      'rating': rating,
      'score': score,
      'width': width,
      'height': height,
      'preview_url': previewUrl,
      'sample_url': sampleUrl,
      'file_url': fileUrl,
      'file_ext': fileExt,
      'has_children': hasChildren,
      'local_path': localPath, // 在这里包含它，方便调试和转换
    };
  }
}
