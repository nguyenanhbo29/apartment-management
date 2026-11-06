import 'package:apartment_management/app.dart';
import 'package:apartment_management/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"success":true,"data":{"status":"ok"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('App khởi động và hiển thị trạng thái backend', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = _FakeAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quản lý chung cư'), findsOneWidget);
    expect(find.text('Backend: ok'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
