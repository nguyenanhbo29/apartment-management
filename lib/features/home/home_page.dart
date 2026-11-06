import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

/// Trang tạm của Bước 0: kiểm tra app gọi được backend (GET /health).
/// Sẽ được thay bằng Login/Dashboard ở Bước 1.
final _healthProvider = FutureProvider.autoDispose<String>((ref) async {
  final data = await ref.watch(apiClientProvider).get<Map<String, dynamic>>('/health');
  return data['status'] as String;
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(_healthProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý chung cư')),
      body: Center(
        child: health.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is ApiException ? e.message : 'Lỗi: $e',
              textAlign: TextAlign.center,
            ),
          ),
          data: (status) => Text('Backend: $status'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.invalidate(_healthProvider),
        tooltip: 'Kiểm tra lại',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
