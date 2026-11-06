import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Callback gọi khi server trả 401 (token hết hạn) để đăng xuất.
/// Module Auth (Bước 1) sẽ gắn vào provider này.
class UnauthorizedHandler extends Notifier<void Function()?> {
  @override
  void Function()? build() => null;

  void set(void Function()? handler) => state = handler;
}

final onUnauthorizedProvider =
    NotifierProvider<UnauthorizedHandler, void Function()?>(UnauthorizedHandler.new);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ref.read(tokenStorageProvider).read();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (err, handler) {
        final ex = ApiException.fromDio(err);
        if (ex.isUnauthorized) ref.read(onUnauthorizedProvider)?.call();
        handler.next(err.copyWith(error: ex));
      },
    ),
  );
  return dio;
});

/// Bọc gọi API: trả về `data` của response chuẩn, ném [ApiException] khi lỗi.
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<T> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.request<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
      return res.data?['data'] as T;
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! as ApiException : ApiException.fromDio(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      request<T>('GET', path, query: query);
  Future<T> post<T>(String path, {Object? body}) => request<T>('POST', path, body: body);
  Future<T> patch<T>(String path, {Object? body}) => request<T>('PATCH', path, body: body);
  Future<T> delete<T>(String path) => request<T>('DELETE', path);
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));
