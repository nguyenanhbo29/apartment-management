import 'dart:convert';

import 'package:apartment_management/app.dart';
import 'package:apartment_management/core/network/api_client.dart';
import 'package:apartment_management/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryTokenStorage extends TokenStorage {
  MemoryTokenStorage([this.token]);
  String? token;

  @override
  Future<String?> read() async => token;
  @override
  Future<void> save(String t) async => token = t;
  @override
  Future<void> clear() async => token = null;
}

typedef FakeHandler = (int, Object?) Function(RequestOptions req);

/// Adapter giả lập backend: trả response theo handler.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final FakeHandler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(int, Object?) okJson(Object? data, [Map<String, dynamic>? meta]) =>
    (200, {'success': true, 'data': data, 'meta': ?meta});

(int, Object?) errJson(int status, String code, String message) => (
  status,
  {
    'success': false,
    'error': {'code': code, 'message': message},
  },
);

Map<String, dynamic> userJson({
  String id = 'u1',
  String email = 'resident@test.local',
  String fullName = 'Nguyễn Văn A',
  String role = 'resident',
  String? department,
  String status = 'active',
  bool mustChangePassword = false,
}) => {
  '_id': id,
  'email': email,
  'fullName': fullName,
  'role': role,
  'department': department,
  'status': status,
  'mustChangePassword': mustChangePassword,
};

Widget buildTestApp({required FakeAdapter adapter, required MemoryTokenStorage tokens}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
  return ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio), tokenStorageProvider.overrideWithValue(tokens)],
    child: const App(),
  );
}
