import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Callback gọi khi server trả 401 (token hết hạn/bị vô hiệu) để đăng xuất.
/// Được gắn ở `App` (lib/app.dart).
class UnauthorizedHandler extends Notifier<void Function()?> {
  @override
  void Function()? build() => null;

  void set(void Function()? handler) => state = handler;
}

final onUnauthorizedProvider = NotifierProvider<UnauthorizedHandler, void Function()?>(
  UnauthorizedHandler.new,
);

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

/// Kết quả có phân trang: `{ success, data: [...], meta: { page, limit, total, totalPages } }`
class Paged<T> {
  const Paged({required this.items, required this.page, required this.total});
  final List<T> items;
  final int page;
  final int total;
}

/// Bọc gọi API theo format chung, ném [ApiException] khi lỗi.
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  /// Trả về toàn bộ body `{ success, data, meta? }`.
  Future<Map<String, dynamic>> envelope(
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
      return res.data ?? const {};
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! as ApiException : ApiException.fromDio(e);
    }
  }

  /// Trả về phần `data` của response.
  Future<T> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final env = await envelope(method, path, body: body, query: query);
    return env['data'] as T;
  }

  Future<Paged<T>> getPaged<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) async {
    final env = await envelope('GET', path, query: query);
    final meta = (env['meta'] as Map?) ?? const {};
    return Paged(
      items: (env['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
      page: (meta['page'] as num?)?.toInt() ?? 1,
      total: (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      request<T>('GET', path, query: query);
  Future<T> post<T>(String path, {Object? body}) => request<T>('POST', path, body: body);
  Future<T> patch<T>(String path, {Object? body}) => request<T>('PATCH', path, body: body);
  Future<T> delete<T>(String path) => request<T>('DELETE', path);
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));
