import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_api.dart';

AppUser _u(UserRole role, [Department? dept]) => AppUser(
  id: 'x',
  email: 'x@test.local',
  fullName: 'X',
  role: role,
  department: dept,
  status: UserStatus.active,
);

const _dashboard = {
  'range': {'from': '2026-10-10', 'to': '2026-11-08'},
  'apartments': {'total': 5, 'occupied': 4, 'occupancyRate': 0.8},
  'requests': {
    'byStatus': {'pending': 3, 'in_progress': 2, 'closed': 7},
    'open': 2,
    'pending': 3,
    'overdue': 1,
    'createdInRange': 12,
  },
  'tasks': {
    'byStatus': <String, int>{},
    'open': 0,
    'overdue': 0,
    'createdInRange': 0,
  },
  'bookings': {
    'total': 6,
    'byAmenity': [
      {
        'amenityId': 'a1',
        'name': 'Hồ bơi',
        'total': 4,
        'byStatus': {'confirmed': 4},
      },
      {
        'amenityId': 'a2',
        'name': 'Khu BBQ',
        'total': 2,
        'byStatus': {'pending': 2},
      },
    ],
  },
  'vehicles': {'pending': 2},
  'visitors': {'expectedToday': 3},
};

Map<String, dynamic> _row(
  String name, {
  int completed = 0,
  double? onTimeRate,
  double? rating,
  int transferredAway = 0,
}) => {
  'staff': {
    '_id': name,
    'fullName': name,
    'department': 'technical',
    'status': 'active',
  },
  'assigned': completed,
  'transferredAway': transferredAway,
  'completed': completed,
  'onTime': 0,
  'onTimeRate': onTimeRate,
  'avgHandlingHours': null,
  'avgRating': rating,
  'ratingCount': rating == null ? 0 : 1,
  'reopenCount': 0,
};

Future<FakeAdapter> _open(
  WidgetTester tester,
  String route,
  (int, Object?)? Function(RequestOptions req) handler,
) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = FakeAdapter((req) {
    final custom = handler(req);
    if (custom != null) return custom;
    switch (req.path) {
      case '/users/me':
        return okJson(userJson(role: 'manager'));
      case '/notifications/unread-count':
        return okJson({'count': 0});
    }
    return okJson(<Object>[], {'page': 1, 'limit': 20, 'total': 0});
  });
  await tester.pumpWidget(
    buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  container.read(routerProvider).push(route);
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  test('M9: chỉ Manager mở dashboard / báo cáo', () {
    for (final u in [
      _u(UserRole.staff, Department.technical),
      _u(UserRole.resident),
      _u(UserRole.accountant),
    ]) {
      expect(authRedirect(AsyncData(u), '/dashboard'), '/');
      expect(authRedirect(AsyncData(u), '/reports/staff'), '/');
    }
    expect(authRedirect(AsyncData(_u(UserRole.manager)), '/dashboard'), isNull);
  });

  testWidgets(
    'dashboard: thẻ số từ API, bấm "Phiếu quá hạn" mở hàng chờ đã lọc',
    (tester) async {
      final adapter = await _open(
        tester,
        '/dashboard',
        (req) =>
            req.path == '/dashboard/operations' ? okJson(_dashboard) : null,
      );

      // Mặc định 30 ngày gần nhất
      final q = adapter.requests
          .firstWhere((r) => r.path == '/dashboard/operations')
          .queryParameters;
      expect(q.keys, containsAll(['from', 'to']));

      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('12 phiếu mới trong kỳ'), findsOneWidget);
      expect(find.text('Hồ bơi'), findsOneWidget);
      // Quá hạn > 0: biểu tượng cảnh báo, không chỉ đổi màu
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.text('Phiếu quá hạn'));
      await tester.pumpAndSettle();
      final queue = adapter.requests.lastWhere(
        (r) => r.path == '/service-requests',
      );
      expect(queue.queryParameters['overdue'], 'true');
    },
  );

  testWidgets(
    'báo cáo hiệu suất: "—" khi chưa có dữ liệu, sắp xếp, lọc bộ phận',
    (tester) async {
      final adapter = await _open(
        tester,
        '/reports/staff',
        (req) => req.path == '/reports/staff-performance'
            ? okJson({
                'range': {'from': '2026-10-10', 'to': '2026-11-08'},
                'totals': {
                  'assigned': 5,
                  'completed': 4,
                  'onTime': 3,
                  'onTimeRate': 0.75,
                  'reopenCount': 1,
                },
                'items': [
                  _row('An', completed: 3, onTimeRate: 0.5, rating: 4.5),
                  _row('Bình', completed: 1, onTimeRate: 1, transferredAway: 7),
                  _row('Cường'),
                ],
              })
            : null,
      );

      expect(find.text('75%'), findsOneWidget); // tổng đúng hạn
      expect(find.text('4.5 ★'), findsOneWidget);
      // Cột mới: việc bị chuyển sang người khác
      expect(find.text('Bị chuyển đi'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      // Cường chưa có việc: "—" chứ không phải 0%
      expect(find.text('0%'), findsNothing);
      expect(find.text('—'), findsWidgets);

      // Mặc định: Hoàn thành giảm dần (An 3 > Bình 1), không phải theo cột khác
      expect(
        tester.getTopLeft(find.text('An')).dy,
        lessThan(tester.getTopLeft(find.text('Bình')).dy),
      );

      // Sắp theo "Đúng hạn" tăng dần: null luôn xuống cuối
      // "Đúng hạn" có cả ở thẻ tổng -> chỉ bấm tiêu đề cột trong bảng
      await tester.tap(
        find.descendant(of: find.byType(DataTable), matching: find.text('Đúng hạn')),
      );
      await tester.pumpAndSettle();
      final names = ['An', 'Bình', 'Cường'];
      double y(String n) => tester.getTopLeft(find.text(n)).dy;
      final ordered = [...names]..sort((a, b) => y(a).compareTo(y(b)));
      expect(ordered.last, 'Cường');

      await tester.tap(find.widgetWithText(FilterChip, 'Bảo vệ'));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['department'], 'security');
    },
  );
}
