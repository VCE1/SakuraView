// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_hive_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PostHiveModelAdapter extends TypeAdapter<PostHiveModel> {
  @override
  final int typeId = 0;

  @override
  PostHiveModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PostHiveModel()
      ..id = fields[0] as int
      ..tags = fields[1] as String?
      ..author = fields[2] as String?
      ..creatorId = fields[3] as int?
      ..source = fields[4] as String?
      ..fileSize = fields[5] as int?
      ..createdAt = fields[6] as int?
      ..rating = fields[7] as String?
      ..score = fields[8] as int?
      ..width = fields[9] as int?
      ..height = fields[10] as int?
      ..previewUrl = fields[11] as String?
      ..sampleUrl = fields[12] as String?
      ..fileUrl = fields[13] as String?
      ..fileExt = fields[14] as String?
      ..hasChildren = fields[15] as bool?
      ..localPath = fields[16] as String?;
  }

  @override
  void write(BinaryWriter writer, PostHiveModel obj) {
    writer
      ..writeByte(17) // 字段总数是 17 (0 到 16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.tags)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.creatorId)
      ..writeByte(4)
      ..write(obj.source)
      ..writeByte(5)
      ..write(obj.fileSize)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.rating)
      ..writeByte(8)
      ..write(obj.score)
      ..writeByte(9)
      ..write(obj.width)
      ..writeByte(10)
      ..write(obj.height)
      ..writeByte(11)
      ..write(obj.previewUrl)
      ..writeByte(12)
      ..write(obj.sampleUrl)
      ..writeByte(13)
      ..write(obj.fileUrl)
      ..writeByte(14)
      ..write(obj.fileExt)
      ..writeByte(15)
      ..write(obj.hasChildren)
      ..writeByte(16)
      ..write(obj.localPath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostHiveModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
