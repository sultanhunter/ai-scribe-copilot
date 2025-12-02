class AudioChunk {
  final String chunkId;
  final String sessionId;
  final int sequenceNumber;
  final String localPath;
  final bool isUploaded;
  final int retryCount;
  final DateTime createdAt;
  final String? presignedUrl;
  final int? fileSize;

  AudioChunk({
    required this.chunkId,
    required this.sessionId,
    required this.sequenceNumber,
    required this.localPath,
    this.isUploaded = false,
    this.retryCount = 0,
    DateTime? createdAt,
    this.presignedUrl,
    this.fileSize,
  }) : createdAt = createdAt ?? DateTime.now();

  AudioChunk copyWith({
    String? chunkId,
    String? sessionId,
    int? sequenceNumber,
    String? localPath,
    bool? isUploaded,
    int? retryCount,
    DateTime? createdAt,
    String? presignedUrl,
    int? fileSize,
  }) {
    return AudioChunk(
      chunkId: chunkId ?? this.chunkId,
      sessionId: sessionId ?? this.sessionId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      localPath: localPath ?? this.localPath,
      isUploaded: isUploaded ?? this.isUploaded,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      presignedUrl: presignedUrl ?? this.presignedUrl,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chunkId': chunkId,
      'sessionId': sessionId,
      'sequenceNumber': sequenceNumber,
      'localPath': localPath,
      'isUploaded': isUploaded,
      'retryCount': retryCount,
      'createdAt': createdAt.toIso8601String(),
      'presignedUrl': presignedUrl,
      'fileSize': fileSize,
    };
  }

  factory AudioChunk.fromJson(Map<String, dynamic> json) {
    return AudioChunk(
      chunkId: json['chunkId'] ?? '',
      sessionId: json['sessionId'] ?? '',
      sequenceNumber: json['sequenceNumber'] ?? 0,
      localPath: json['localPath'] ?? '',
      isUploaded: json['isUploaded'] ?? false,
      retryCount: json['retryCount'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      presignedUrl: json['presignedUrl'],
      fileSize: json['fileSize'],
    );
  }
}
