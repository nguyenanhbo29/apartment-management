import 'package:flutter/material.dart';

import '../../auth/data/app_user.dart';

/// Chọn vai trò + bộ phận (bộ phận chỉ hiện khi là Nhân viên). Dùng cho UC-04, UC-05.
class RoleFields extends StatelessWidget {
  const RoleFields({
    super.key,
    required this.role,
    required this.department,
    required this.onRoleChanged,
    required this.onDepartmentChanged,
  });

  final UserRole role;
  final Department? department;
  final ValueChanged<UserRole> onRoleChanged;
  final ValueChanged<Department?> onDepartmentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<UserRole>(
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Vai trò'),
          items: [
            for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label)),
          ],
          onChanged: (r) {
            if (r != null) onRoleChanged(r);
          },
        ),
        if (role == UserRole.staff) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<Department>(
            initialValue: department,
            decoration: const InputDecoration(labelText: 'Bộ phận'),
            validator: (d) => d == null ? 'Nhân viên phải có bộ phận' : null,
            items: [
              for (final d in Department.values) DropdownMenuItem(value: d, child: Text(d.label)),
            ],
            onChanged: onDepartmentChanged,
          ),
        ],
      ],
    );
  }
}
