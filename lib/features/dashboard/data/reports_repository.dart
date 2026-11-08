import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/data/app_user.dart';
import 'models.dart';

/// UC-47, UC-48 (phần Người 2). Ngày gửi dạng yyyy-MM-dd, backend hiểu theo giờ VN.
class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Map<String, dynamic> _range(DateTimeRange r) => {
    'from': apiDate(r.start),
    'to': apiDate(r.end),
  };

  Future<OperationsDashboard> operations(DateTimeRange range) async =>
      OperationsDashboard.fromJson(
        await _api.get<Map<String, dynamic>>(
          '/dashboard/operations',
          query: _range(range),
        ),
      );

  Future<StaffPerformanceReport> staffPerformance(
    DateTimeRange range, {
    Department? department,
  }) async => StaffPerformanceReport.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/reports/staff-performance',
      query: {..._range(range), 'department': ?department?.name},
    ),
  );
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);
