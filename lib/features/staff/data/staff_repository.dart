import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/app_user.dart';

/// Nhân viên kèm tải việc đang mở (UC-40).
class StaffMember {
  const StaffMember({
    required this.user,
    required this.openRequests,
    required this.openTasks,
  });

  final AppUser user;
  final int openRequests;
  final int openTasks;

  int get openWork => openRequests + openTasks;

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    user: AppUser.fromJson(json),
    openRequests: (json['openRequests'] as num?)?.toInt() ?? 0,
    openTasks: (json['openTasks'] as num?)?.toInt() ?? 0,
  );
}

/// Bộ phận (cố định, enum) kèm số nhân viên.
class DepartmentSummary {
  const DepartmentSummary({
    required this.department,
    required this.activeStaff,
    required this.totalStaff,
  });

  final Department department;
  final int activeStaff;
  final int totalStaff;

  static DepartmentSummary? fromJson(Map<String, dynamic> json) {
    final d = Department.parse(json['code'] as String?);
    if (d == null) return null;
    return DepartmentSummary(
      department: d,
      activeStaff: (json['activeStaff'] as num?)?.toInt() ?? 0,
      totalStaff: (json['totalStaff'] as num?)?.toInt() ?? 0,
    );
  }
}

/// UC-40: nhân viên theo bộ phận. Thêm/sửa/khóa dùng UsersRepository (M1).
class StaffRepository {
  StaffRepository(this._api);
  final ApiClient _api;

  Future<Paged<StaffMember>> list({
    Department? department,
    UserStatus? status,
    String q = '',
    int page = 1,
  }) => _api.getPaged(
    '/staff',
    StaffMember.fromJson,
    query: {
      'department': ?department?.name,
      'status': ?status?.name,
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'page': page,
      'limit': 20,
    },
  );

  Future<List<DepartmentSummary>> departments() async {
    final data = await _api.get<List<dynamic>>('/staff/departments');
    return data
        .map((e) => DepartmentSummary.fromJson(e as Map<String, dynamic>))
        .whereType<DepartmentSummary>()
        .toList();
  }
}

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(apiClientProvider)),
);
