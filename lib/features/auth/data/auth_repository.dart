import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import 'app_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<AppUser> login(String email, String password) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    await _tokens.save(data['token'] as String);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Khôi phục phiên khi mở app. Trả null nếu chưa đăng nhập hoặc token
  /// không còn hợp lệ; ném lỗi nếu mất mạng (để hiển thị nút thử lại).
  Future<AppUser?> restoreSession() async {
    final token = await _tokens.read();
    if (token == null) return null;
    try {
      return AppUser.fromJson(await _api.get<Map<String, dynamic>>('/users/me'));
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _api.post<dynamic>('/auth/logout');
    } catch (_) {
      // Bỏ qua lỗi mạng: vẫn xóa token phía client
    }
    await _tokens.clear();
  }

  Future<void> clearToken() => _tokens.clear();

  /// Trả về mã OTP demo khi backend chạy MAIL_MODE=console, ngược lại null.
  Future<String?> forgotPassword(String email) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/forgot-password',
      body: {'email': email.trim()},
    );
    return data['devOtp'] as String?;
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) => _api.post<dynamic>(
    '/auth/reset-password',
    body: {'email': email.trim(), 'otp': otp.trim(), 'newPassword': newPassword},
  );

  Future<AppUser> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    await _tokens.save(data['token'] as String);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser> updateProfile({required String fullName, String? phone}) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/users/me',
      body: {
        'fullName': fullName.trim(),
        'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      },
    );
    return AppUser.fromJson(data);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);
