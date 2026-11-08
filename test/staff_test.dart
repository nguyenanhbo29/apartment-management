import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
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

Map<String, dynamic> _staff(
  String id,
  String name,
  String dept,
  int requests,
  int tasks,
) => {
  ...userJson(
    id: id,
    email: '$id@test.local',
    fullName: name,
    role: 'staff',
    department: dept,
  ),
  'openRequests': requests,
  'openTasks': tasks,
};

void main() {
  test('UC-40: chỉ Manager mở được /staff', () {
    expect(authRedirect(AsyncData(_u(UserRole.manager)), '/staff'), isNull);
    expect(
      authRedirect(
        AsyncData(_u(UserRole.staff, Department.technical)),
        '/staff',
      ),
      '/',
    );
    expect(authRedirect(AsyncData(_u(UserRole.resident)), '/staff'), '/');
  });

  testWidgets('Manager xem nhân viên theo bộ phận kèm tải việc', (
    tester,
  ) async {
    final adapter = FakeAdapter((req) {
      switch (req.path) {
        case '/users/me':
          return okJson(userJson(role: 'manager', fullName: 'QL'));
        case '/notifications/unread-count':
          return okJson({'count': 0});
        case '/staff/departments':
          return okJson([
            {'code': 'reception', 'activeStaff': 1, 'totalStaff': 1},
            {'code': 'security', 'activeStaff': 1, 'totalStaff': 1},
            {'code': 'technical', 'activeStaff': 2, 'totalStaff': 3},
            {'code': 'facility', 'activeStaff': 0, 'totalStaff': 0},
          ]);
        case '/staff':
          final dept = req.queryParameters['department'];
          final all = [
            _staff('s1', 'Ngô Nam', 'technical', 3, 2),
            _staff('s2', 'Đỗ Long', 'technical', 0, 0),
            _staff('s3', 'Phạm Hùng', 'security', 1, 0),
          ];
          final items = dept == null
              ? all
              : all.where((s) => s['department'] == dept).toList();
          return okJson(items, {'page': 1, 'limit': 20, 'total': items.length});
      }
      return okJson(null);
    });

    await tester.pumpWidget(
      buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhân viên'));
    await tester.pumpAndSettle();

    // Tab "Tất cả": đủ 3 người, mức tải theo số việc
    expect(find.text('Ngô Nam'), findsOneWidget);
    expect(find.text('Phạm Hùng'), findsOneWidget);
    expect(
      find.text('5 việc'),
      findsOneWidget,
    ); // 3 phiếu + 2 nhiệm vụ -> nhiều việc
    expect(find.text('Rảnh'), findsOneWidget);
    // Mặc định chỉ lấy nhân viên đang làm
    expect(adapter.requests.last.queryParameters['status'], 'active');

    // Tab bộ phận hiển thị số nhân viên đang làm, chỉ lấy đúng bộ phận
    await tester.tap(find.text('Kỹ thuật (2)'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['department'], 'technical');
    expect(find.text('Phạm Hùng'), findsNothing);
    expect(find.text('Đỗ Long'), findsOneWidget);
  });
}
