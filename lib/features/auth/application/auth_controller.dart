import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_user.dart';
import '../data/auth_repository.dart';

/// Trạng thái đăng nhập toàn app.
///   AsyncLoading  -> đang khôi phục phiên (màn splash)
///   AsyncData(null) -> chưa đăng nhập
///   AsyncData(user) -> đã đăng nhập
///   AsyncError    -> không kết nối được server khi khôi phục phiên
class AuthController extends AsyncNotifier<AppUser?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AppUser?> build() => _repo.restoreSession();

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.restoreSession);
  }

  /// Ném ApiException khi thất bại để màn hình hiển thị lỗi.
  Future<void> login(String email, String password) async {
    final user = await _repo.login(email, password);
    state = AsyncData(user);
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(null);
  }

  /// Gọi khi API trả 401 (token hết hạn / mật khẩu đã đổi ở thiết bị khác).
  Future<void> forceLogout() async {
    if (state.value == null) return;
    await _repo.clearToken();
    state = const AsyncData(null);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = await _repo.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    state = AsyncData(user);
  }

  Future<void> updateProfile({required String fullName, String? phone}) async {
    final user = await _repo.updateProfile(fullName: fullName, phone: phone);
    state = AsyncData(user);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
  // Không tự retry: màn splash có nút "Thử lại"
  retry: (_, _) => null,
);

/// Người dùng hiện tại (null nếu chưa đăng nhập).
final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authControllerProvider).value);
