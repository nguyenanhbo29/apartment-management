import 'package:dio/dio.dart';

/// Lỗi chuẩn hóa từ response `{ success:false, error:{ code, message, details } }`.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final List<dynamic>? details;

  bool get isUnauthorized => statusCode == 401;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        code: (err['code'] ?? 'UNKNOWN').toString(),
        message: (err['message'] ?? 'Đã có lỗi xảy ra').toString(),
        statusCode: e.response?.statusCode,
        details: err['details'] as List<dynamic>?,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ApiException(
          code: 'NETWORK_ERROR',
          message: 'Không kết nối được máy chủ. Vui lòng kiểm tra mạng.',
        );
      default:
        return ApiException(
          code: 'UNKNOWN',
          message: 'Đã có lỗi xảy ra',
          statusCode: e.response?.statusCode,
        );
    }
  }

  @override
  String toString() => 'ApiException($code, $message)';
}
