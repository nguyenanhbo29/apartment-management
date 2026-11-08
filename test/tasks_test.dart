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

Map<String, dynamic> _task({
  String status = 'assigned',
  List<String> actions = const [],
}) => {
  '_id': 't1',
  'taskCode': 'TK-ABC234',
  'title': 'Kiểm tra bình chữa cháy',
  'category': 'inspection',
  'location': 'Khối A',
  'priority': 'high',
  'department': 'technical',
  'assignedStaffId': {'_id': 's1', 'fullName': 'Ngô Nam'},
  'createdBy': {'_id': 'm1', 'fullName': 'Quản Lý'},
  'deadline': '2026-11-20T10:00:00.000Z',
  'status': status,
  'isOverdue': false,
  'timeline': [
    {
      'action': 'created',
      'updatedBy': {'_id': 'm1', 'fullName': 'Quản Lý'},
      'assignedStaffId': {'_id': 's1', 'fullName': 'Ngô Nam'},
      'createdAt': '2026-11-08T03:00:00.000Z',
    },
  ],
  'allowedActions': actions,
};

Map<String, dynamic> _request() => {
  '_id': 'r1',
  'kind': 'request',
  'requestCode': 'SR-XYZ789',
  'requestType': 'repair',
  'category': 'electric',
  'title': 'Mất điện phòng khách',
  'description': 'x',
  'priority': 'normal',
  'status': 'assigned',
  'isOverdue': false,
  'deadline': '2026-11-19T10:00:00.000Z',
};

Future<FakeAdapter> _open(
  WidgetTester tester,
  String route, {
  required String role,
  String? department,
  required (int, Object?)? Function(RequestOptions req) handler,
}) async {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = FakeAdapter((req) {
    final custom = handler(req);
    if (custom != null) return custom;
    switch (req.path) {
      case '/users/me':
        return okJson(userJson(role: role, department: department));
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
  test('M7: luật route theo vai trò', () {
    final manager = AsyncData(_u(UserRole.manager));
    final staff = AsyncData(_u(UserRole.staff, Department.technical));
    final resident = AsyncData(_u(UserRole.resident));
    expect(authRedirect(manager, '/tasks/new'), isNull);
    expect(authRedirect(staff, '/tasks/new'), '/');
    expect(authRedirect(staff, '/tasks'), isNull);
    expect(authRedirect(staff, '/tasks/t1'), isNull);
    expect(authRedirect(staff, '/tasks/t1/reassign'), '/');
    expect(authRedirect(resident, '/tasks'), '/');
  });

  testWidgets('Việc của tôi hiển thị cả phiếu và nhiệm vụ, mở đúng chi tiết', (
    tester,
  ) async {
    await _open(
      tester,
      '/assignments',
      role: 'staff',
      department: 'technical',
      handler: (req) => switch (req.path) {
        '/me/assignments' => okJson(
          [
            _request(),
            {..._task(), 'kind': 'task'},
          ],
          {'page': 1, 'limit': 20, 'total': 2},
        ),
        '/tasks/t1' => okJson(_task(actions: ['start'])),
        _ => null,
      },
    );
    expect(find.text('Mất điện phòng khách'), findsOneWidget);
    expect(find.text('Kiểm tra bình chữa cháy'), findsOneWidget);
    expect(find.text('Nhiệm vụ'), findsOneWidget);

    await tester.tap(find.text('Kiểm tra bình chữa cháy'));
    await tester.pumpAndSettle();
    expect(find.text('TK-ABC234'), findsOneWidget);
    expect(find.text('Tạo và giao việc'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Bắt đầu'), findsOneWidget);
  });

  testWidgets('nhân viên hoàn thành nhiệm vụ: gửi multipart kèm kết quả', (
    tester,
  ) async {
    FormData? sent;
    await _open(
      tester,
      '/tasks/t1',
      role: 'staff',
      department: 'technical',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/tasks/t1') => okJson(
          _task(status: 'in_progress', actions: ['complete']),
        ),
        ('PATCH', '/tasks/t1/complete') => () {
          sent = req.data as FormData;
          return okJson(_task(status: 'completed'));
        }(),
        _ => null,
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Hoàn thành'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Đã thay 2 bình');
    await tester.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await tester.pumpAndSettle();
    expect(Map.fromEntries(sent!.fields), {'note': 'Đã thay 2 bình'});
    expect(find.text('Đã báo hoàn thành'), findsOneWidget);
  });

  testWidgets('Manager giao nhiệm vụ: chọn người phụ trách rồi gửi', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await _open(
      tester,
      '/tasks/new',
      role: 'manager',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/staff') => okJson(
          [
            {
              ...userJson(
                id: 's1',
                fullName: 'Ngô Nam',
                role: 'staff',
                department: 'technical',
              ),
              'openRequests': 1,
              'openTasks': 0,
            },
          ],
          {'page': 1, 'limit': 100, 'total': 1},
        ),
        ('POST', '/tasks') => () {
          sent = req.data as Map<String, dynamic>;
          return (201, {'success': true, 'data': _task()});
        }(),
        _ => null,
      },
    );

    // Thiếu tiêu đề: báo lỗi form, không gửi
    await tester.tap(find.widgetWithText(FilledButton, 'Giao nhiệm vụ'));
    await tester.pumpAndSettle();
    expect(find.text('Tiêu đề tối thiểu 3 ký tự'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tiêu đề'),
      'Vệ sinh hầm B1',
    );
    // Chưa chọn người: báo lỗi
    await tester.tap(find.widgetWithText(FilledButton, 'Giao nhiệm vụ'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nhân viên phụ trách'), findsOneWidget);
    expect(sent, isNull);

    await tester.tap(find.text('Ngô Nam'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Giao nhiệm vụ'));
    await tester.pumpAndSettle();
    expect(sent, containsPair('title', 'Vệ sinh hầm B1'));
    expect(sent, containsPair('staffId', 's1'));
    expect(sent, containsPair('department', 'technical'));
    expect(sent, containsPair('category', 'inspection'));
    expect(sent!['deadline'], isA<String>());
  });

  testWidgets('Staff mở /tasks: là lịch sử của mình, không có nút giao việc', (
    tester,
  ) async {
    await _open(
      tester,
      '/tasks',
      role: 'staff',
      department: 'technical',
      handler: (req) => req.path == '/tasks'
          ? okJson(
              [_task(status: 'completed')],
              {'page': 1, 'limit': 20, 'total': 1},
            )
          : null,
    );
    expect(find.text('Lịch sử nhiệm vụ'), findsOneWidget);
    expect(find.text('Giao nhiệm vụ'), findsNothing);
    expect(find.text('Kiểm tra bình chữa cháy'), findsOneWidget);
  });
}
