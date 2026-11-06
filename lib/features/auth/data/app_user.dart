enum UserRole {
  resident('Cư dân'),
  staff('Nhân viên'),
  manager('Quản lý'),
  accountant('Kế toán');

  const UserRole(this.label);
  final String label;

  static UserRole parse(String? v) =>
      UserRole.values.firstWhere((e) => e.name == v, orElse: () => UserRole.resident);
}

enum Department {
  reception('Lễ tân'),
  security('Bảo vệ'),
  technical('Kỹ thuật'),
  facility('Tiện ích');

  const Department(this.label);
  final String label;

  static Department? parse(String? v) {
    for (final d in Department.values) {
      if (d.name == v) return d;
    }
    return null;
  }
}

enum UserStatus {
  active('Đang hoạt động'),
  inactive('Đã khóa');

  const UserStatus(this.label);
  final String label;

  static UserStatus parse(String? v) => v == 'inactive' ? UserStatus.inactive : UserStatus.active;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.phone,
    this.avatarUrl,
    this.department,
    this.mustChangePassword = false,
    this.lastLoginAt,
    this.createdAt,
  });

  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final UserRole role;
  final Department? department;
  final UserStatus status;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  bool get isActive => status == UserStatus.active;
  bool get isManager => role == UserRole.manager;
  bool get isResident => role == UserRole.resident;

  /// Được xem toàn bộ căn hộ / hồ sơ cư dân: Quản lý, Kế toán, Nhân viên Lễ tân.
  bool get canViewResidents =>
      role == UserRole.manager ||
      role == UserRole.accountant ||
      (role == UserRole.staff && department == Department.reception);

  /// Nhãn vai trò, kèm bộ phận nếu là nhân viên. Vd: "Nhân viên · Bảo vệ"
  String get roleLabel => department == null ? role.label : '${role.label} · ${department!.label}';

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.last.substring(0, 1).toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: (json['_id'] ?? json['id']).toString(),
    email: json['email'] as String,
    fullName: json['fullName'] as String,
    phone: json['phone'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    role: UserRole.parse(json['role'] as String?),
    department: Department.parse(json['department'] as String?),
    status: UserStatus.parse(json['status'] as String?),
    mustChangePassword: json['mustChangePassword'] == true,
    lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? '')?.toLocal(),
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
  );
}
