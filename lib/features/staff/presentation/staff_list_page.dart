import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/app_user.dart';
import '../application/staff_providers.dart';
import '../data/staff_repository.dart';

/// UC-40: Nhân viên theo bộ phận + số việc đang mở (Manager).
/// Thêm/sửa/khóa nhân viên: mở chi tiết tài khoản (M1).
class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({super.key});

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  UserStatus _status = UserStatus.active;
  int _reload = 0;

  // Tab 0 = tất cả, sau đó theo thứ tự Department.values
  static const _tabs = <Department?>[null, ...Department.values];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => setState(() => _q = q.trim()),
    );
  }

  Future<void> _openDetail(StaffMember s) async {
    await context.push('/users/${s.user.id}');
    ref.invalidate(departmentSummariesProvider);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(departmentSummariesProvider).value ?? const [];
    String tabLabel(Department? d) {
      if (d == null) return 'Tất cả';
      final s = summaries.where((e) => e.department == d).firstOrNull;
      return s == null ? d.label : '${d.label} (${s.activeStaff})';
    }

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhân viên'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final d in _tabs) Tab(text: tabLabel(d))],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'Tìm theo tên, email, số điện thoại',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  for (final s in UserStatus.values) ...[
                    ChoiceChip(
                      label: Text(
                        s == UserStatus.active ? 'Đang làm' : 'Đã khóa',
                      ),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final d in _tabs)
                    PagedListView<StaffMember>(
                      key: ValueKey('${d?.name}|${_status.name}|$_q|$_reload'),
                      fetch: (page) => ref
                          .read(staffRepositoryProvider)
                          .list(
                            department: d,
                            status: _status,
                            q: _q,
                            page: page,
                          ),
                      emptyText: 'Không có nhân viên phù hợp',
                      itemBuilder: (context, s) => StaffTile(
                        staff: s,
                        showDepartment: d == null,
                        onTap: () => _openDetail(s),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một dòng nhân viên: tên, bộ phận, tải việc. Dùng lại ở màn phân công (M5, M7).
class StaffTile extends StatelessWidget {
  const StaffTile({
    super.key,
    required this.staff,
    this.showDepartment = true,
    this.onTap,
  });

  final StaffMember staff;
  final bool showDepartment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final u = staff.user;
    final parts = [
      if (showDepartment && u.department != null) u.department!.label,
      if ((u.phone ?? '').isNotEmpty) u.phone!,
      u.email,
    ];
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text(u.initials)),
      title: Text(u.fullName),
      subtitle: Text(
        '${parts.join(' · ')}\n${staff.openRequests} phiếu · ${staff.openTasks} nhiệm vụ đang mở',
      ),
      isThreeLine: true,
      trailing: u.isActive
          ? WorkloadChip(openWork: staff.openWork)
          : const StatusChip(label: 'Đã khóa', tone: StatusTone.danger),
    );
  }
}

/// Mức tải việc: rảnh / bình thường / nhiều việc.
class WorkloadChip extends StatelessWidget {
  const WorkloadChip({super.key, required this.openWork});

  final int openWork;

  @override
  Widget build(BuildContext context) => switch (openWork) {
    0 => const StatusChip(label: 'Rảnh', tone: StatusTone.success),
    < 4 => StatusChip(label: '$openWork việc', tone: StatusTone.info),
    _ => StatusChip(label: '$openWork việc', tone: StatusTone.warning),
  };
}
