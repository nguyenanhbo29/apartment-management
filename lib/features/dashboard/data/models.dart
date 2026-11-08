import '../../../core/utils/json.dart';
import '../../auth/data/app_user.dart';

double? _double(Object? v) => (v as num?)?.toDouble();
Map<String, int> _counts(Object? v) => {
  for (final e in ((v as Map?) ?? const {}).entries)
    e.key.toString(): (e.value as num).toInt(),
};

/// UC-47. byStatus/open/overdue là số hiện tại; createdInRange, đặt tiện ích trong khoảng.
class OperationsDashboard {
  const OperationsDashboard({
    required this.from,
    required this.to,
    required this.apartmentsTotal,
    required this.apartmentsOccupied,
    required this.occupancyRate,
    required this.requestsByStatus,
    required this.requestsOpen,
    required this.requestsPending,
    required this.requestsOverdue,
    required this.requestsCreated,
    required this.tasksOpen,
    required this.tasksOverdue,
    required this.tasksCreated,
    required this.bookingsTotal,
    required this.bookingsByAmenity,
    required this.vehiclesPending,
    required this.visitorsToday,
  });

  final String from;
  final String to;
  final int apartmentsTotal;
  final int apartmentsOccupied;
  final double? occupancyRate;
  final Map<String, int> requestsByStatus;
  final int requestsOpen;
  final int requestsPending;
  final int requestsOverdue;
  final int requestsCreated;
  final int tasksOpen;
  final int tasksOverdue;
  final int tasksCreated;
  final int bookingsTotal;
  final List<(String name, int total)> bookingsByAmenity;
  final int vehiclesPending;
  final int visitorsToday;

  factory OperationsDashboard.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) =>
        (j[k] as Map<String, dynamic>?) ?? const {};
    final apt = m('apartments');
    final req = m('requests');
    final task = m('tasks');
    final book = m('bookings');
    return OperationsDashboard(
      from: m('range')['from'] as String? ?? '',
      to: m('range')['to'] as String? ?? '',
      apartmentsTotal: intOf(apt['total']) ?? 0,
      apartmentsOccupied: intOf(apt['occupied']) ?? 0,
      occupancyRate: _double(apt['occupancyRate']),
      requestsByStatus: _counts(req['byStatus']),
      requestsOpen: intOf(req['open']) ?? 0,
      requestsPending: intOf(req['pending']) ?? 0,
      requestsOverdue: intOf(req['overdue']) ?? 0,
      requestsCreated: intOf(req['createdInRange']) ?? 0,
      tasksOpen: intOf(task['open']) ?? 0,
      tasksOverdue: intOf(task['overdue']) ?? 0,
      tasksCreated: intOf(task['createdInRange']) ?? 0,
      bookingsTotal: intOf(book['total']) ?? 0,
      bookingsByAmenity: [
        for (final a in (book['byAmenity'] as List?) ?? const [])
          ((a as Map)['name'] as String? ?? '—', intOf(a['total']) ?? 0),
      ],
      vehiclesPending: intOf(m('vehicles')['pending']) ?? 0,
      visitorsToday: intOf(m('visitors')['expectedToday']) ?? 0,
    );
  }
}

/// UC-48: một dòng nhân viên. Các chỉ số null = chưa có dữ liệu (hiển thị "—").
class StaffPerformanceRow {
  const StaffPerformanceRow({
    required this.staffId,
    required this.fullName,
    required this.department,
    required this.isActive,
    required this.assigned,
    this.transferredAway = 0,
    required this.completed,
    required this.onTime,
    required this.onTimeRate,
    required this.avgHandlingHours,
    required this.avgRating,
    required this.ratingCount,
    required this.reopenCount,
  });

  final String staffId;
  final String fullName;
  final Department? department;
  final bool isActive;
  final int assigned;

  /// Việc được giao trong kỳ nhưng sau đó đã chuyển sang người khác.
  final int transferredAway;
  final int completed;
  final int onTime;
  final double? onTimeRate;
  final double? avgHandlingHours;
  final double? avgRating;
  final int ratingCount;
  final int reopenCount;

  factory StaffPerformanceRow.fromJson(Map<String, dynamic> j) {
    final staff = (j['staff'] as Map<String, dynamic>?) ?? const {};
    return StaffPerformanceRow(
      staffId: staff['_id'] as String? ?? '',
      fullName: staff['fullName'] as String? ?? '',
      department: Department.parse(staff['department'] as String?),
      isActive: staff['status'] != 'inactive',
      assigned: intOf(j['assigned']) ?? 0,
      transferredAway: intOf(j['transferredAway']) ?? 0,
      completed: intOf(j['completed']) ?? 0,
      onTime: intOf(j['onTime']) ?? 0,
      onTimeRate: _double(j['onTimeRate']),
      avgHandlingHours: _double(j['avgHandlingHours']),
      avgRating: _double(j['avgRating']),
      ratingCount: intOf(j['ratingCount']) ?? 0,
      reopenCount: intOf(j['reopenCount']) ?? 0,
    );
  }
}

class StaffPerformanceReport {
  const StaffPerformanceReport({
    required this.from,
    required this.to,
    required this.rows,
    required this.totalAssigned,
    required this.totalCompleted,
    required this.totalOnTimeRate,
  });

  final String from;
  final String to;
  final List<StaffPerformanceRow> rows;
  final int totalAssigned;
  final int totalCompleted;
  final double? totalOnTimeRate;

  factory StaffPerformanceReport.fromJson(Map<String, dynamic> j) {
    final range = (j['range'] as Map<String, dynamic>?) ?? const {};
    final totals = (j['totals'] as Map<String, dynamic>?) ?? const {};
    return StaffPerformanceReport(
      from: range['from'] as String? ?? '',
      to: range['to'] as String? ?? '',
      rows: [
        for (final r in (j['items'] as List?) ?? const [])
          StaffPerformanceRow.fromJson(r as Map<String, dynamic>),
      ],
      totalAssigned: intOf(totals['assigned']) ?? 0,
      totalCompleted: intOf(totals['completed']) ?? 0,
      totalOnTimeRate: _double(totals['onTimeRate']),
    );
  }
}
