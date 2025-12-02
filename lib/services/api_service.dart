import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import '../models/patient.dart';
import '../models/recording_session.dart';

class ApiService {
  late final Dio _dio;
  final Logger _logger = Logger();

  ApiService({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _logger.d('REQUEST[${options.method}] => ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.d('RESPONSE[${response.statusCode}] => ${response.data}');
          return handler.next(response);
        },
        onError: (error, handler) {
          _logger.e('ERROR[${error.response?.statusCode}] => ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  // Patient Management
  Future<List<Patient>> getPatients(String userId) async {
    try {
      final response = await _dio.get(
        '/${AppConstants.apiVersion}/patients',
        queryParameters: {'userId': userId},
      );

      if (response.data['patients'] != null) {
        return (response.data['patients'] as List)
            .map((json) => Patient.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching patients: $e');
      rethrow;
    }
  }

  Future<Patient> addPatient(Patient patient, String userId) async {
    try {
      final response = await _dio.post(
        '/${AppConstants.apiVersion}/add-patient-ext',
        data: {...patient.toJson(), 'userId': userId},
      );

      return Patient.fromJson(response.data);
    } catch (e) {
      _logger.e('Error adding patient: $e');
      rethrow;
    }
  }

  // Session Management
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/${AppConstants.apiVersion}/upload-session',
        data: {'patientId': patientId, 'userId': userId},
      );

      return {
        'sessionId': response.data['sessionId'],
        'uploadUrl': response.data['uploadUrl'],
      };
    } catch (e) {
      _logger.e('Error creating session: $e');
      rethrow;
    }
  }

  Future<String> getPresignedUrl({
    required String sessionId,
    required String chunkId,
    required int sequenceNumber,
  }) async {
    try {
      final response = await _dio.post(
        '/${AppConstants.apiVersion}/get-presigned-url',
        data: {
          'sessionId': sessionId,
          'chunkId': chunkId,
          'sequenceNumber': sequenceNumber,
        },
      );

      return response.data['presignedUrl'];
    } catch (e) {
      _logger.e('Error getting presigned URL: $e');
      rethrow;
    }
  }

  Future<void> uploadChunk(String presignedUrl, List<int> audioData) async {
    try {
      await _dio.put(
        presignedUrl,
        data: audioData,
        options: Options(headers: {'Content-Type': 'audio/wav'}),
      );
    } catch (e) {
      _logger.e('Error uploading chunk: $e');
      rethrow;
    }
  }

  Future<void> notifyChunkUploaded({
    required String sessionId,
    required String chunkId,
    required int sequenceNumber,
    String? checksum,
  }) async {
    try {
      await _dio.post(
        '/${AppConstants.apiVersion}/notify-chunk-uploaded',
        data: {
          'sessionId': sessionId,
          'chunkId': chunkId,
          'sequenceNumber': sequenceNumber,
          if (checksum != null) 'checksum': checksum,
        },
      );
    } catch (e) {
      _logger.e('Error notifying chunk uploaded: $e');
      rethrow;
    }
  }

  Future<List<RecordingSession>> getSessionsByPatient(String patientId) async {
    try {
      final response = await _dio.get(
        '/${AppConstants.apiVersion}/fetch-session-by-patient/$patientId',
      );

      if (response.data['sessions'] != null) {
        return (response.data['sessions'] as List)
            .map((json) => RecordingSession.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      _logger.e('Error fetching sessions: $e');
      rethrow;
    }
  }
}
