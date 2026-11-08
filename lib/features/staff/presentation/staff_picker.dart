import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../data/staff_repository.dart';
import 'staff_list_page.dart';

/// Chọn nhân viên đang làm của một bộ phận, ít việc lên trước để cân tải.
/// Dùng cho phân công phiếu (M5) và nhiệm vụ (M7). Đổi bộ phận thì đổi `key` để tải lại.
class StaffPicker extends ConsumerStatefulWidget {
  const StaffPicker({
    super.key,
    required this.department,
    required this.onSelected,
    this.selectedId,
    this.excludeId,
  });

  final Department department;
  final String? selectedId;

  /// Bỏ khỏi danh sách (vd người đang được giao, khi chuyển người).
  final String? excludeId;
  final ValueChanged<StaffMember> onSelected;

  @override
  ConsumerState<StaffPicker> createState() => _StaffPickerState();
}

class _StaffPickerState extends ConsumerState<StaffPicker> {
  late final Future<Paged<StaffMember>> _future = ref
      .read(staffRepositoryProvider)
      .list(
        department: widget.department,
        status: UserStatus.active,
        page: 1,
        limit: 100,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!);
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final staff =
            snap.data!.items
                .where((s) => s.user.id != widget.excludeId)
                .toList()
              ..sort((a, b) => a.openWork.compareTo(b.openWork));
        if (staff.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Bộ phận này chưa có nhân viên đang làm'),
          );
        }
        return Column(
          children: [
            for (final s in staff)
              // Material (không phải Container màu) để ListTile vẫn hiện hiệu ứng chạm
              Material(
                color: s.user.id == widget.selectedId
                    ? Theme.of(context).colorScheme.primaryContainer
                          .withValues(alpha: 0.4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: StaffTile(
                  staff: s,
                  showDepartment: false,
                  onTap: () => widget.onSelected(s),
                ),
              ),
          ],
        );
      },
    );
  }
}
