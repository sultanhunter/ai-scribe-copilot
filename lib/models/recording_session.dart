class RecordingSession {
  final String sessionId;
  final String patientId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // recording, paused, completed, failed
  final int totalChunks;
  final int uploadedChunks;
  final String? localPath;

  RecordingSession({
    required this.sessionId,
    required this.patientId,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.totalChunks = 0,
    this.uploadedChunks = 0,
    this.localPath,
  });

  RecordingSession copyWith({
    String? sessionId,
    String? patientId,
    String? userId,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
    int? totalChunks,
    int? uploadedChunks,
    String? localPath,
  }) {
    return RecordingSession(
      sessionId: sessionId ?? this.sessionId,
      patientId: patientId ?? this.patientId,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
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
      'endTime': endTime?.toIso8601String(),
      'status': status,
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
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      status: json['status'] ?? 'recording',
      totalChunks: json['totalChunks'] ?? 0,
      uploadedChunks: json['uploadedChunks'] ?? 0,
      localPath: json['localPath'],
    );
  }

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}
