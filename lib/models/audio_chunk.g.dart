// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_chunk.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudioChunkAdapter extends TypeAdapter<AudioChunk> {
  @override
  final int typeId = 0;

  @override
  AudioChunk read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioChunk(
      chunkId: fields[0] as String,
      sessionId: fields[1] as String,
      sequenceNumber: fields[2] as int,
      localPath: fields[3] as String,
      uploadState: fields[4] as ChunkUploadState,
      retryCount: fields[5] as int,
      createdAt: fields[6] as DateTime?,
      lastAttemptTime: fields[7] as DateTime?,
      presignedUrl: fields[8] as String?,
      fileSize: fields[9] as int?,
      checksum: fields[10] as String?,
      errorMessage: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AudioChunk obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.chunkId)
      ..writeByte(1)
      ..write(obj.sessionId)
      ..writeByte(2)
      ..write(obj.sequenceNumber)
      ..writeByte(3)
      ..write(obj.localPath)
      ..writeByte(4)
      ..write(obj.uploadState)
      ..writeByte(5)
      ..write(obj.retryCount)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.lastAttemptTime)
      ..writeByte(8)
      ..write(obj.presignedUrl)
      ..writeByte(9)
      ..write(obj.fileSize)
      ..writeByte(10)
      ..write(obj.checksum)
      ..writeByte(11)
      ..write(obj.errorMessage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioChunkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
