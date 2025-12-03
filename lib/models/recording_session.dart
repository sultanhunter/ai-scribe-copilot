class RecordingSession {
  final String sessionId;
  final String patientId;
  final String userId;
  final DateTime startTime;
  final int totalChunks;
  final int uploadedChunks;
  final String? localPath;

  RecordingSession({
    required this.sessionId,
    required this.patientId,
    required this.userId,
    required this.startTime,
    this.totalChunks = 0,
    this.uploadedChunks = 0,
    this.localPath,
  });

  RecordingSession copyWith({
    String? sessionId,
    String? patientId,
    String? userId,
    DateTime? startTime,
    int? totalChunks,
    int? uploadedChunks,
    String? localPath,
  }) {
    return RecordingSession(
      sessionId: sessionId ?? this.sessionId,
      patientId: patientId ?? this.patientId,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      totalChunks: totalChunks ?? this.totalChunks,
      uploadedChunks: uploadedChunks ?? this.uploadedChunks,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'patientId': patientId,
      'userId': userId,
      'startTime': startTime.toIso8601String(),
      'totalChunks': totalChunks,
      'uploadedChunks': uploadedChunks,
      'localPath': localPath,
    };
  }

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      sessionId: json['sessionId'] ?? '',
      patientId: json['patientId'] ?? '',
      userId: json['userId'] ?? '',
      startTime: DateTime.parse(json['startTime']),
      totalChunks: json['totalChunks'] ?? 0,
      uploadedChunks: json['uploadedChunks'] ?? 0,
      localPath: json['localPath'],
    );
  }
}
