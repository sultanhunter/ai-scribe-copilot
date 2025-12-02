import 'package:hive/hive.dart';

part 'audio_chunk.g.dart';

enum ChunkUploadState {
  recorded, // Just recorded, waiting to upload
  uploading, // Currently being uploaded
  uploaded, // Successfully uploaded to storage
  verified, // Server confirmed receipt
  failed, // Failed after max retries
}

@HiveType(typeId: 0)
class AudioChunk extends HiveObject {
  @HiveField(0)
  final String chunkId;

  @HiveField(1)
  final String sessionId;

  @HiveField(2)
  final int sequenceNumber;

  @HiveField(3)
  final String localPath;

  @HiveField(4)
  ChunkUploadState uploadState;

  @HiveField(5)
  int retryCount;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  DateTime? lastAttemptTime;

  @HiveField(8)
  String? presignedUrl;

  @HiveField(9)
  final int? fileSize;

  @HiveField(10)
  String? checksum;

  @HiveField(11)
  String? errorMessage;

  AudioChunk({
    required this.chunkId,
    required this.sessionId,
    required this.sequenceNumber,
    required this.localPath,
    this.uploadState = ChunkUploadState.recorded,
    this.retryCount = 0,
    DateTime? createdAt,
    this.lastAttemptTime,
    this.presignedUrl,
    this.fileSize,
    this.checksum,
    this.errorMessage,
  }) : createdAt = createdAt ?? DateTime.now();

  AudioChunk copyWith({
    String? chunkId,
    String? sessionId,
    int? sequenceNumber,
    String? localPath,
    ChunkUploadState? uploadState,
    int? retryCount,
    DateTime? createdAt,
    DateTime? lastAttemptTime,
    String? presignedUrl,
    int? fileSize,
    String? checksum,
    String? errorMessage,
  }) {
    return AudioChunk(
      chunkId: chunkId ?? this.chunkId,
      sessionId: sessionId ?? this.sessionId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      localPath: localPath ?? this.localPath,
      uploadState: uploadState ?? this.uploadState,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptTime: lastAttemptTime ?? this.lastAttemptTime,
      presignedUrl: presignedUrl ?? this.presignedUrl,
      fileSize: fileSize ?? this.fileSize,
      checksum: checksum ?? this.checksum,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chunkId': chunkId,
      'sessionId': sessionId,
      'sequenceNumber': sequenceNumber,
      'localPath': localPath,
      'uploadState': uploadState.toString(),
      'retryCount': retryCount,
      'createdAt': createdAt.toIso8601String(),
      'lastAttemptTime': lastAttemptTime?.toIso8601String(),
      'presignedUrl': presignedUrl,
      'fileSize': fileSize,
      'checksum': checksum,
      'errorMessage': errorMessage,
    };
  }

  factory AudioChunk.fromJson(Map<String, dynamic> json) {
    return AudioChunk(
      chunkId: json['chunkId'] ?? '',
      sessionId: json['sessionId'] ?? '',
      sequenceNumber: json['sequenceNumber'] ?? 0,
      localPath: json['localPath'] ?? '',
      uploadState: ChunkUploadState.values.firstWhere(
        (e) => e.toString() == json['uploadState'],
        orElse: () => ChunkUploadState.recorded,
      ),
      retryCount: json['retryCount'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      lastAttemptTime: json['lastAttemptTime'] != null
          ? DateTime.parse(json['lastAttemptTime'])
          : null,
      presignedUrl: json['presignedUrl'],
      fileSize: json['fileSize'],
      checksum: json['checksum'],
      errorMessage: json['errorMessage'],
    );
  }

  bool get isUploaded =>
      uploadState == ChunkUploadState.uploaded ||
      uploadState == ChunkUploadState.verified;

  bool get canRetry =>
      uploadState == ChunkUploadState.failed &&
      retryCount < 3; // Max retries from constants
}
