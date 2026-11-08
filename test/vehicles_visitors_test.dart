import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
import 'package:apartment_management/features/vehicles/data/models.dart';
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

Map<String, dynamic> _vehicle({
  String status = 'pending',
  List<String> actions = const [],
}) => {
  '_id': 'v1',
  'type': 'motorbike',
  'plateNumber': '30A12345',
  'status': status,
  'brand': 'Honda',
  'apartmentId': {'_id': 'a1', 'code': 'A-101'},
  'ownerId': {'_id': 'u1', 'fullName': 'Chủ Hộ', 'phone': '0901000001'},
  'createdAt': '2026-11-08T03:00:00.000Z',
  'allowedActions': actions,
};

Map<String, dynamic> _visitor({String id = 'g1', String status = 'expected'}) =>
    {
      '_id': id,
      'appointmentCode': 'VS-ABC234',
      'visitorName': 'Nguyễn Khách',
      'visitorPhone': '0912345678',
      'numberOfPeople': 2,
      'status': status,
      'isOverdue': false,
      'apartmentId': {'_id': 'a1', 'code': 'A-101'},
      'timeFrom': '2026-11-08T02:00:00.000Z',
      'timeTo': '2026-11-08T04:00:00.000Z',
    };

/// Mở app đã đăng nhập với [role], rồi đi thẳng tới [route].
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
  test('biển số: chuẩn hóa, kiểm tra, hiển thị', () {
    expect(normalizePlate(' 30a-123.45 '), '30A12345');
    expect(plateRegex.hasMatch(normalizePlate('30a-123.45')), isTrue);
    expect(plateRegex.hasMatch(normalizePlate('ABC-1234')), isFalse);
    expect(formatPlate('30A12345'), '30A-123.45');
    expect(formatPlate('29B1234'), '29B-1234');
  });

  test('M3: luật route theo vai trò', () {
    final resident = AsyncData(_u(UserRole.resident));
    final security = AsyncData(_u(UserRole.staff, Department.security));
    final reception = AsyncData(_u(UserRole.staff, Department.reception));
    final technical = AsyncData(_u(UserRole.staff, Department.technical));
    final accountant = AsyncData(_u(UserRole.accountant));

    expect(authRedirect(resident, '/vehicles/new'), isNull);
    expect(authRedirect(security, '/vehicles/new'), '/');
    expect(authRedirect(security, '/vehicles/manage'), isNull);
    expect(authRedirect(accountant, '/vehicles/manage'), isNull);
    expect(authRedirect(technical, '/vehicles/manage'), '/');
    expect(authRedirect(reception, '/visitors/gate'), isNull);
    expect(authRedirect(technical, '/visitors/gate'), '/');
    expect(authRedirect(resident, '/visitors/gate'), '/');
    expect(authRedirect(resident, '/visitors/new'), isNull);
  });

  testWidgets('cư dân đăng ký xe: biển sai bị chặn, đúng thì gửi multipart', (
    tester,
  ) async {
    FormData? sent;
    await _open(
      tester,
      '/vehicles/new',
      role: 'resident',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/apartments/mine') => okJson([_apt]),
        ('POST', '/vehicles') => () {
          sent = req.data as FormData;
          return (201, {'success': true, 'data': _vehicle()});
        }(),
        _ => null,
      },
    );

    final plate = find.widgetWithText(TextFormField, 'Biển số');
    await tester.enterText(plate, 'ABC-1234');
    await tester.tap(find.text('Gửi đăng ký'));
    await tester.pumpAndSettle();
    expect(find.text('Biển số không đúng định dạng'), findsOneWidget);
    expect(sent, isNull);

    await tester.tap(find.text('Ô tô'));
    await tester.enterText(plate, '30a-123.45');
    await tester.tap(find.text('Gửi đăng ký'));
    await tester.pumpAndSettle();
    expect(Map.fromEntries(sent!.fields), {
      'apartmentId': 'a1',
      'type': 'car',
      'plateNumber': '30a-123.45',
    });
  });

  testWidgets('Bảo vệ duyệt xe chờ duyệt', (tester) async {
    final adapter = await _open(
      tester,
      '/vehicles/v1',
      role: 'staff',
      department: 'security',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/vehicles/v1') => okJson(
          _vehicle(actions: ['approve', 'reject']),
        ),
        ('PATCH', '/vehicles/v1/approve') => okJson(
          _vehicle(status: 'approved'),
        ),
        _ => null,
      },
    );
    expect(find.text('30A-123.45'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Từ chối'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt').last);
    await tester.pumpAndSettle();
    expect(
      adapter.requests.any(
        (r) => r.method == 'PATCH' && r.path == '/vehicles/v1/approve',
      ),
      isTrue,
    );
    expect(find.text('Đã duyệt xe'), findsOneWidget);
  });

  testWidgets('Bảo vệ check-in tại cổng; ngoài khung giờ hiện lỗi từ server', (
    tester,
  ) async {
    var outOfWindow = false;
    final adapter = await _open(
      tester,
      '/visitors/gate',
      role: 'staff',
      department: 'security',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/visitors') => okJson(
          [_visitor(), _visitor(id: 'g2', status: 'checked_in')],
          {'page': 1, 'limit': 50, 'total': 2},
        ),
        ('PATCH', '/visitors/g1/check-in') =>
          outOfWindow
              ? errJson(
                  409,
                  'VISITOR_OUT_OF_WINDOW',
                  'Khách đến ngoài khung giờ đã hẹn',
                )
              : okJson(_visitor(status: 'checked_in')),
        _ => null,
      },
    );

    expect(find.text('Khách hôm nay'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check-in'), findsOneWidget);
    expect(find.text('Check-out'), findsOneWidget);
    // Mặc định không gửi date (backend lấy hôm nay theo giờ VN)
    final list = adapter.requests.firstWhere((r) => r.path == '/visitors');
    expect(list.queryParameters.containsKey('date'), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Đã check-in Nguyễn Khách'), findsOneWidget);

    outOfWindow = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Khách đến ngoài khung giờ đã hẹn'), findsOneWidget);
  });

  testWidgets('Lễ tân xem danh sách cổng nhưng không có nút check-in', (
    tester,
  ) async {
    await _open(
      tester,
      '/visitors/gate',
      role: 'staff',
      department: 'reception',
      handler: (req) => req.path == '/visitors'
          ? okJson([_visitor()], {'page': 1, 'limit': 50, 'total': 1})
          : null,
    );
    expect(find.text('Nguyễn Khách'), findsOneWidget);
    expect(find.text('Check-in'), findsNothing);
  });
}
