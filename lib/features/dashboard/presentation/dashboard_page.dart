import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../service_requests/data/models.dart';
import '../data/models.dart';
import '../data/reports_repository.dart';
import 'widgets.dart';

/// Nhãn ngắn dưới cột (tooltip hiện nhãn đầy đủ).
const _shortStatus = {
  RequestStatus.pending: 'Chờ\nnhận',
  RequestStatus.assigned: 'Đã\ngiao',
  RequestStatus.inProgress: 'Đang\nlàm',
  RequestStatus.waitingConfirmation: 'Chờ\nNT',
  RequestStatus.reopened: 'Làm\nlại',
  RequestStatus.closed: 'Đã\nđóng',
  RequestStatus.rejected: 'Từ\nchối',
};

/// UC-47: Dashboard vận hành (Manager). Số liệu thật; bấm vào số để mở danh sách nguồn.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  RangePreset _preset = RangePreset.last30;
  late DateTimeRange _range = RangePreset.last30.resolve(DateTime.now())!;
  late Future<OperationsDashboard> _future = _load();

  Future<OperationsDashboard> _load() =>
      ref.read(reportsRepositoryProvider).operations(_range);

  // Thân khối, không dùng `=>`: setState không được trả về Future
  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _open(String route) async {
    await context.push(route);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard vận hành'),
        actions: [
          IconButton(
            tooltip: 'Báo cáo hiệu suất',
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => context.push('/reports/staff'),
          ),
        ],
      ),
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
          Expanded(
            child: FutureBuilder<OperationsDashboard>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorView(error: snap.error!, onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!;
                final statuses = RequestStatus.values;
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [
                      Text(
                        'Số đang mở / quá hạn là hiện tại; số mới và lượt đặt tính từ '
                        '${formatDate(DateTime.parse(d.from))} đến ${formatDate(DateTime.parse(d.to))}.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.45,
                        children: [
                          StatTile(
                            label: 'Căn hộ có người ở',
                            value:
                                '${d.apartmentsOccupied}/${d.apartmentsTotal}',
                            caption: percent(d.occupancyRate),
                            icon: Icons.apartment_outlined,
                            onTap: () => _open('/apartments'),
                          ),
                          StatTile(
                            label: 'Phiếu chờ tiếp nhận',
                            value: '${d.requestsPending}',
                            caption: '${d.requestsCreated} phiếu mới trong kỳ',
                            icon: Icons.inbox_outlined,
                            onTap: () => _open('/requests/queue'),
                          ),
                          StatTile(
                            label: 'Phiếu quá hạn',
                            value: '${d.requestsOverdue}',
                            caption: '${d.requestsOpen} phiếu đang xử lý',
                            icon: Icons.schedule,
                            alert: d.requestsOverdue > 0,
                            onTap: () =>
                                _open('/requests/queue?filter=overdue'),
                          ),
                          StatTile(
                            label: 'Nhiệm vụ quá hạn',
                            value: '${d.tasksOverdue}',
                            caption: '${d.tasksOpen} nhiệm vụ đang mở',
                            icon: Icons.task_alt,
                            alert: d.tasksOverdue > 0,
                            onTap: () => _open('/tasks?filter=overdue'),
                          ),
                          StatTile(
                            label: 'Xe chờ duyệt',
                            value: '${d.vehiclesPending}',
                            icon: Icons.two_wheeler_outlined,
                            onTap: () => _open('/vehicles/manage'),
                          ),
                          StatTile(
                            label: 'Khách hẹn hôm nay',
                            value: '${d.visitorsToday}',
                            caption: 'chưa đến',
                            icon: Icons.door_front_door_outlined,
                            onTap: () => _open('/visitors/gate'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Phiếu theo trạng thái (hiện tại)',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Chạm vào cột để xem danh sách',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SimpleBarChart(
                        data: [
                          for (final s in statuses)
                            BarDatum(
                              label: s.label,
                              shortLabel: _shortStatus[s]!,
                              value: d.requestsByStatus[s.api] ?? 0,
                            ),
                        ],
                        onTap: (i) =>
                            _open('/requests/queue?status=${statuses[i].api}'),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lượt đặt tiện ích trong kỳ',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${d.bookingsTotal}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      d.bookingsByAmenity.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Chưa có lượt đặt trong kỳ'),
                            )
                          : BarList(
                              items: d.bookingsByAmenity,
                              onTap: () => _open('/bookings/queue'),
                            ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
