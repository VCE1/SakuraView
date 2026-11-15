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
      ..localPath = fields[16] as String?
      ..parentId = fields[17] as int?
      ..siteName = fields[18] as String?
      ..uploader = fields[19] as String?
      ..artistTags = (fields[20] as List?)?.cast<String>()
      ..characterTags = (fields[21] as List?)?.cast<String>()
      ..copyrightTags = (fields[22] as List?)?.cast<String>()
      ..generalTags = (fields[23] as List?)?.cast<String>()
      ..metaTags = (fields[24] as List?)?.cast<String>()
      ..previewWidth = fields[25] as int?
      ..previewHeight = fields[26] as int?
      ..poolId = fields[27] as int?
      ..poolName = fields[28] as String?
      ..pixivId = fields[29] as int?
      ..downloadedQuality = fields[30] as String?;
  }

  @override
  void write(BinaryWriter writer, PostHiveModel obj) {
    writer
      ..writeByte(31)
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
      ..write(obj.localPath)
      ..writeByte(17)
      ..write(obj.parentId)
      ..writeByte(18)
      ..write(obj.siteName)
      ..writeByte(19)
      ..write(obj.uploader)
      ..writeByte(20)
      ..write(obj.artistTags)
      ..writeByte(21)
      ..write(obj.characterTags)
      ..writeByte(22)
      ..write(obj.copyrightTags)
      ..writeByte(23)
      ..write(obj.generalTags)
      ..writeByte(24)
      ..write(obj.metaTags)
      ..writeByte(25)
      ..write(obj.previewWidth)
      ..writeByte(26)
      ..write(obj.previewHeight)
      ..writeByte(27)
      ..write(obj.poolId)
      ..writeByte(28)
      ..write(obj.poolName)
      ..writeByte(29)
      ..write(obj.pixivId)
      ..writeByte(30)
      ..write(obj.downloadedQuality);
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
