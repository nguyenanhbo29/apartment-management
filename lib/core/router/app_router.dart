import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_page.dart';

/// Router gốc. Các module thêm route ở các bước sau; Bước 1 sẽ thêm
/// redirect theo trạng thái đăng nhập và role.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
    ],
  );
});
