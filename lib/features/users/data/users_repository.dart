import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/app_user.dart';

class UserFilter {
  const UserFilter({this.q = '', this.role, this.status});

  final String q;
  final UserRole? role;
  final UserStatus? status;

  UserFilter copyWith({String? q, UserRole? Function()? role, UserStatus? Function()? status}) =>
      UserFilter(
        q: q ?? this.q,
        role: role != null ? role() : this.role,
        status: status != null ? status() : this.status,
      );

  Map<String, dynamic> toQuery() => {
    if (q.trim().isNotEmpty) 'q': q.trim(),
    if (role != null) 'role': role!.name,
    if (status != null) 'status': status!.name,
  };
}

/// UC-04, UC-05: API quản lý tài khoản (chỉ Manager).
class UsersRepository {
  UsersRepository(this._api);
  final ApiClient _api;

  Future<Paged<AppUser>> list({UserFilter filter = const UserFilter(), int page = 1}) =>
      _api.getPaged(
        '/users',
        AppUser.fromJson,
        query: {...filter.toQuery(), 'page': page, 'limit': 20},
      );

  Future<AppUser> get(String id) async =>
      AppUser.fromJson(await _api.get<Map<String, dynamic>>('/users/$id'));

  Future<AppUser> create({
    required String email,
    required String fullName,
    String? phone,
    required UserRole role,
    Department? department,
    required String password,
  }) async => AppUser.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/users',
      body: {
        'email': email.trim(),
        'fullName': fullName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'role': role.name,
        if (role == UserRole.staff) 'department': department?.name,
        'password': password,
      },
    ),
  );

  Future<AppUser> update(String id, {required String fullName, String? phone}) async =>
      AppUser.fromJson(
        await _api.patch<Map<String, dynamic>>(
          '/users/$id',
          body: {
            'fullName': fullName.trim(),
            'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
          },
        ),
      );

  Future<AppUser> setStatus(String id, UserStatus status) async => AppUser.fromJson(
    await _api.patch<Map<String, dynamic>>('/users/$id/status', body: {'status': status.name}),
  );

  Future<AppUser> setRole(String id, UserRole role, Department? department) async =>
      AppUser.fromJson(
        await _api.patch<Map<String, dynamic>>(
          '/users/$id/role',
          body: {'role': role.name, if (role == UserRole.staff) 'department': department?.name},
        ),
      );

  Future<AppUser> resetPassword(String id, String password) async => AppUser.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/users/$id/reset-password',
      body: {'password': password},
    ),
  );
}

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(apiClientProvider)),
);
