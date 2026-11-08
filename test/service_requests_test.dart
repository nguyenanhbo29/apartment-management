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

Map<String, dynamic> _req({
  String id = 'r1',
  String status = 'pending',
  List<String> actions = const [],
  bool overdue = false,
}) => {
  '_id': id,
  'requestCode': 'SR-ABC234',
  'requestType': 'repair',
  'category': 'electric',
  'title': 'Mất điện phòng khách',
  'description': 'Ổ cắm không có điện',
  'priority': 'high',
  'status': status,
  'isOverdue': overdue,
  'apartmentId': {'_id': 'a1', 'code': 'A-101'},
  'createdBy': {'_id': 'u1', 'fullName': 'Chủ Hộ'},
  'images': <String>[],
  'resultImages': <String>[],
  'createdAt': '2026-11-08T03:00:00.000Z',
  'timeline': [
    {
      'action': 'created',
      'newStatus': 'pending',
      'updatedBy': {'_id': 'u1', 'fullName': 'Chủ Hộ'},
      'createdAt': '2026-11-08T03:00:00.000Z',
    },
  ],
  'allowedActions': actions,
};

const _apt = {
  '_id': 'a1',
  'code': 'A-101',
  'floor': 1,
  'area': 70,
  'status': 'occupied',
  'residentCount': 2,
  'ownerName': 'Chủ Hộ',
  'myMembership': {'id': 'm1', 'relation': 'owner', 'isPayer': true},
};

const _paged = {'page': 1, 'limit': 20, 'total': 1};

void main() {
  test('M5: luật route theo vai trò', () {
    final resident = AsyncData(_u(UserRole.resident));
    final manager = AsyncData(_u(UserRole.manager));
    final staff = AsyncData(_u(UserRole.staff, Department.technical));

    expect(authRedirect(resident, '/requests'), isNull);
    expect(authRedirect(resident, '/requests/new'), isNull);
    expect(authRedirect(resident, '/requests/queue'), '/');
    expect(authRedirect(manager, '/requests/queue'), isNull);
    expect(authRedirect(manager, '/requests/r1/assign'), isNull);
    expect(authRedirect(staff, '/requests/r1/assign'), '/');
    expect(authRedirect(staff, '/assignments'), isNull);
    expect(authRedirect(resident, '/assignments'), '/');
    // Chi tiết: mọi vai trò (backend lọc phạm vi)
    for (final u in [resident, manager, staff]) {
      expect(authRedirect(u, '/requests/r1'), isNull);
    }
  });

  testWidgets('cư dân tạo phiếu: validate form, gửi multipart đúng trường', (
    tester,
  ) async {
    // Màn hình cao để cả form được build (ListView chỉ build phần đang hiện)
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FormData? sent;
    final adapter = FakeAdapter((req) {
      switch ((req.method, req.path)) {
        case ('GET', '/users/me'):
          return okJson(userJson(fullName: 'Chủ Hộ'));
        case ('GET', '/notifications/unread-count'):
          return okJson({'count': 0});
        case ('GET', '/service-requests/mine'):
          return okJson([_req()], _paged);
        case ('GET', '/apartments/mine'):
          return okJson([_apt]);
        case ('POST', '/service-requests'):
          sent = req.data as FormData;
          return (201, {'success': true, 'data': _req(id: 'r2')});
      }
      return okJson(null);
    });

    await tester.pumpWidget(
      buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phiếu của tôi'));
    await tester.pumpAndSettle();
    expect(find.text('Mất điện phòng khách'), findsOneWidget);
    expect(find.text('Chờ tiếp nhận'), findsWidgets);

    await tester.tap(find.text('Tạo phiếu'));
    await tester.pumpAndSettle();

    // Gửi trống: báo lỗi, không gọi API
    final submit = find.text('Gửi phiếu');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Chọn danh mục'), findsOneWidget);
    expect(find.text('Tiêu đề tối thiểu 3 ký tự'), findsOneWidget);
    expect(find.text('Mô tả tối thiểu 5 ký tự'), findsOneWidget);
    expect(sent, isNull);

    // Điền đủ rồi gửi (một căn hộ -> không cần chọn)
    await tester.tap(find.text('Phản ánh'));
    await tester.tap(find.text('Danh mục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếng ồn').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tiêu đề'),
      'Hàng xóm hát karaoke',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mô tả chi tiết'),
      'Hát karaoke sau 23h mỗi tối',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    final fields = Map.fromEntries(sent!.fields);
    expect(fields, {
      'apartmentId': 'a1',
      'requestType': 'complaint',
      'category': 'noise',
      'priority': 'normal',
      'title': 'Hàng xóm hát karaoke',
      'description': 'Hát karaoke sau 23h mỗi tối',
    });
    // Quay về danh sách sau khi gửi
    expect(find.text('Phiếu của tôi'), findsOneWidget);
  });

  Future<FakeAdapter> openDetail(
    WidgetTester tester, {
    required String role,
    required Map<String, dynamic> request,
    String? department,
    (int, Object?) Function(RequestOptions req)? onPatch,
  }) async {
    final adapter = FakeAdapter((req) {
      if (req.method == 'PATCH') return onPatch?.call(req) ?? okJson(request);
      switch (req.path) {
        case '/users/me':
          return okJson(userJson(role: role, department: department));
        case '/notifications/unread-count':
          return okJson({'count': 0});
        case '/service-requests/r1':
          return okJson(request);
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
    container.read(routerProvider).push('/requests/r1');
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('nút theo allowedActions: Manager thấy Phân công / Từ chối', (
    tester,
  ) async {
    await openDetail(
      tester,
      role: 'manager',
      request: _req(actions: ['assign', 'reject']),
    );
    expect(find.text('SR-ABC234'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Phân công'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Từ chối'), findsOneWidget);
    expect(find.text('Nghiệm thu'), findsNothing);
    expect(find.text('Tạo phiếu'), findsWidgets); // timeline
  });

  testWidgets(
    'cư dân phiếu chờ nghiệm thu: thấy Nghiệm thu / Yêu cầu làm lại',
    (tester) async {
      await openDetail(
        tester,
        role: 'resident',
        request: _req(
          status: 'waiting_confirmation',
          actions: ['confirm', 'reopen'],
        ),
      );
      expect(find.text('Chờ nghiệm thu'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Nghiệm thu'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Yêu cầu làm lại'),
        findsOneWidget,
      );
    },
  );

  testWidgets('không có quyền thao tác: không có thanh nút', (tester) async {
    await openDetail(
      tester,
      role: 'resident',
      request: _req(status: 'in_progress'),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets(
    'nhân viên bắt đầu xử lý; 409 INVALID_STATE thì báo phiếu đã thay đổi',
    (tester) async {
      final adapter = await openDetail(
        tester,
        role: 'staff',
        department: 'technical',
        request: _req(status: 'assigned', actions: ['start'], overdue: true),
        onPatch: (_) =>
            errJson(409, 'INVALID_STATE', 'Phiếu đã thay đổi trạng thái'),
      );
      expect(find.text('Quá hạn'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu xử lý'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
      await tester.pumpAndSettle();

      final patch = adapter.requests.where((r) => r.method == 'PATCH').single;
      expect(patch.path, '/service-requests/r1/start');
      expect(find.text('Phiếu đã thay đổi, đã tải lại'), findsOneWidget);
      // Tải lại chi tiết sau lỗi
      expect(
        adapter.requests
            .where((r) => r.path == '/service-requests/r1' && r.method == 'GET')
            .length,
        2,
      );
    },
  );
}
