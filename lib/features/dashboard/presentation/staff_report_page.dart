import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../data/models.dart';
import '../data/reports_repository.dart';
import 'widgets.dart';

/// UC-48 (phần Người 2): Báo cáo hiệu suất nhân viên. Bảng sắp xếp được, lọc theo bộ phận.
/// Chỉ số chưa có dữ liệu hiển thị "—" (khác 0%).
class StaffReportPage extends ConsumerStatefulWidget {
  const StaffReportPage({super.key});

  @override
  ConsumerState<StaffReportPage> createState() => _StaffReportPageState();
}

typedef _Column = (
  String label,
  String tooltip,
  Comparable<dynamic>? Function(StaffPerformanceRow r),
);

class _StaffReportPageState extends ConsumerState<StaffReportPage> {
  RangePreset _preset = RangePreset.last30;
  late DateTimeRange _range = RangePreset.last30.resolve(DateTime.now())!;
  Department? _department;
  int _sortColumn = 2;
  bool _ascending = false;
  late Future<StaffPerformanceReport> _future = _load();

  Future<StaffPerformanceReport> _load() => ref
      .read(reportsRepositoryProvider)
      .staffPerformance(_range, department: _department);

  // Thân khối, không dùng `=>`: setState không được trả về Future
  void _reload() => setState(() {
    _future = _load();
  });

  static final List<_Column> _columns = [
    ('Nhân viên', 'Họ tên', (r) => r.fullName),
    (
      'Được giao',
      'Số lần được giao việc (phiếu + nhiệm vụ) trong kỳ',
      (r) => r.assigned,
    ),
    (
      'Hoàn thành',
      'Phiếu: lần báo xong đầu tiên. Nhiệm vụ: lúc hoàn thành',
      (r) => r.completed,
    ),
    (
      'Đúng hạn',
      'Hoàn thành trước hạn / tổng hoàn thành (theo lúc nhân viên báo xong)',
      (r) => r.onTimeRate,
    ),
    (
      'TG xử lý',
      'Trung bình từ lúc được giao tới lúc hoàn thành (giờ)',
      (r) => r.avgHandlingHours,
    ),
    (
      'Đánh giá',
      'Điểm trung bình cư dân chấm cho phiếu đã đóng trong kỳ',
      (r) => r.avgRating,
    ),
    ('Làm lại', 'Số lần cư dân yêu cầu làm lại', (r) => r.reopenCount),
  ];

  List<StaffPerformanceRow> _sorted(List<StaffPerformanceRow> rows) {
    final key = _columns[_sortColumn].$3;
    // null ("—") luôn xuống cuối dù sắp tăng hay giảm
    return [...rows]..sort((a, b) {
      final ka = key(a);
      final kb = key(b);
      if (ka == null && kb == null) return 0;
      if (ka == null) return 1;
      if (kb == null) return -1;
      final c = ka.compareTo(kb);
      return _ascending ? c : -c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hiệu suất nhân viên')),
      body: Column(
        children: [
          RangeSelector(
            preset: _preset,
            range: _range,
            onChanged: (p, r) => setState(() {
              _preset = p;
              _range = r;
              _future = _load();
            }),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final d in <Department?>[null, ...Department.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(d?.label ?? 'Mọi bộ phận'),
                      selected: _department == d,
                      onSelected: (_) {
                        _department = d;
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<StaffPerformanceReport>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorView(error: snap.error!, onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final report = snap.data!;
                if (report.rows.isEmpty) {
                  return const Center(child: Text('Không có nhân viên'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Được giao',
                            value: '${report.totalAssigned}',
                            icon: Icons.assignment_ind_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: 'Hoàn thành',
                            value: '${report.totalCompleted}',
                            icon: Icons.task_alt,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: 'Đúng hạn',
                            value: percent(report.totalOnTimeRate),
                            icon: Icons.timer_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        sortColumnIndex: _sortColumn,
                        sortAscending: _ascending,
                        columnSpacing: 20,
                        columns: [
                          for (final (i, c) in _columns.indexed)
                            DataColumn(
                              label: Text(c.$1),
                              tooltip: c.$2,
                              numeric: i > 0,
                              onSort: (col, asc) => setState(() {
                                _sortColumn = col;
                                _ascending = asc;
                              }),
                            ),
                        ],
                        rows: [
                          for (final r in _sorted(report.rows))
                            DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(r.fullName),
                                      Text(
                                        [
                                          r.department?.label ?? '—',
                                          if (!r.isActive) 'đã khóa',
                                        ].join(' · '),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text('${r.assigned}')),
                                DataCell(Text('${r.completed}')),
                                DataCell(Text(percent(r.onTimeRate))),
                                DataCell(
                                  Text(
                                    dash(r.avgHandlingHours, (h) => '${h}h'),
                                  ),
                                ),
                                DataCell(
                                  Text(dash(r.avgRating, (x) => '$x ★')),
                                ),
                                DataCell(Text('${r.reopenCount}')),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"—": chưa có dữ liệu trong kỳ (khác 0%). Giữ ngón tay trên tiêu đề cột để xem cách tính.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
