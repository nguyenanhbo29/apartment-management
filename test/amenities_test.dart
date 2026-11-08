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

const _amenity = {
  '_id': 'am1',
  'name': 'Hồ bơi',
  'location': 'Tầng 5',
  'openTime': '06:00',
  'closeTime': '10:00',
  'slotDuration': 60,
  'capacity': 10,
  'requiresApproval': false,
  'cancelDeadlineHours': 2,
  'status': 'active',
  'rules': 'Mặc đồ bơi',
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

/// Slot dựng từ giờ máy -> nhãn 'HH:mm' đúng dù máy test ở múi giờ nào.
Map<String, dynamic> _slot(int hour, int remaining) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day + 1, hour);
  return {
    'start': start.toUtc().toIso8601String(),
    'end': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    'used': 10 - remaining,
    'remaining': remaining,
    'available': remaining > 0,
  };
}

Map<String, dynamic> _booking({
  String status = 'pending',
  List<String> actions = const [],
}) => {
  '_id': 'b1',
  'amenityId': {'_id': 'am1', 'name': 'Khu BBQ', 'location': 'Sân thượng'},
  'apartmentId': {'_id': 'a1', 'code': 'A-101'},
  'bookedBy': {'_id': 'u1', 'fullName': 'Chủ Hộ'},
  'startTime': '2026-11-10T09:00:00.000Z',
  'endTime': '2026-11-10T11:00:00.000Z',
  'numberOfParticipants': 6,
  'status': status,
  'cancelDeadline': '2026-11-09T09:00:00.000Z',
  'allowedActions': actions,
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
  test('M6: luật route theo vai trò', () {
    final resident = AsyncData(_u(UserRole.resident));
    final manager = AsyncData(_u(UserRole.manager));
    final facility = AsyncData(_u(UserRole.staff, Department.facility));
    final security = AsyncData(_u(UserRole.staff, Department.security));

    expect(authRedirect(resident, '/amenities/am1'), isNull);
    expect(authRedirect(resident, '/amenities/new'), '/');
    expect(authRedirect(manager, '/amenities/am1/edit'), isNull);
    expect(authRedirect(resident, '/bookings'), isNull);
    expect(authRedirect(facility, '/bookings/queue'), isNull);
    expect(authRedirect(manager, '/bookings/queue'), isNull);
    expect(authRedirect(security, '/bookings/queue'), '/');
  });

  testWidgets('cư dân chọn slot và đặt; hết chỗ thì báo và tải lại lưới', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    var full = false;
    final adapter = await _open(
      tester,
      '/amenities/am1',
      role: 'resident',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/amenities/am1') => okJson(_amenity),
        ('GET', '/amenities/am1/slots') => okJson([
          _slot(6, 0),
          _slot(7, 4),
          _slot(8, 10),
        ]),
        ('GET', '/apartments/mine') => okJson([_apt]),
        ('POST', '/amenity-bookings') => () {
          sent = req.data as Map<String, dynamic>;
          return full
              ? errJson(
                  409,
                  'SLOT_FULL',
                  'Khung giờ đã đầy, vui lòng chọn khung khác',
                )
              : (201, {'success': true, 'data': _booking(status: 'confirmed')});
        }(),
        _ => null,
      },
    );

    expect(find.text('Nội quy'), findsOneWidget);
    expect(find.text('Hết chỗ'), findsOneWidget);
    expect(find.text('Còn 4'), findsOneWidget);

    // Slot hết chỗ: bấm không mở gì
    await tester.tap(find.text('06:00–07:00'));
    await tester.pumpAndSettle();
    expect(find.text('Số người'), findsNothing);

    await tester.tap(find.text('07:00–08:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thêm'));
    await tester.tap(find.byTooltip('Thêm'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đặt'));
    await tester.pumpAndSettle();

    expect(sent, containsPair('startTime', '07:00'));
    expect(sent, containsPair('numberOfParticipants', 3));
    expect(sent, containsPair('amenityId', 'am1'));
    expect(sent, containsPair('apartmentId', 'a1'));
    expect(find.text('Đặt thành công'), findsOneWidget);

    // Hết chỗ do người khác vừa đặt: báo lỗi server và tải lại lưới
    full = true;
    final before = adapter.requests
        .where((r) => r.path == '/amenities/am1/slots')
        .length;
    await tester.tap(find.text('08:00–09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đặt'));
    await tester.pumpAndSettle();
    expect(
      find.text('Khung giờ đã đầy, vui lòng chọn khung khác'),
      findsOneWidget,
    );
    expect(
      adapter.requests.where((r) => r.path == '/amenities/am1/slots').length,
      greaterThan(before),
    );
  });

  testWidgets('nhân viên tiện ích duyệt lượt đặt chờ duyệt', (tester) async {
    final adapter = await _open(
      tester,
      '/bookings/b1',
      role: 'staff',
      department: 'facility',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/amenity-bookings/b1') => okJson(
          _booking(actions: ['approve', 'reject']),
        ),
        ('PATCH', '/amenity-bookings/b1/approve') => okJson(
          _booking(status: 'confirmed'),
        ),
        _ => null,
      },
    );
    expect(find.text('Khu BBQ'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt').last);
    await tester.pumpAndSettle();
    expect(
      adapter.requests.any(
        (r) => r.method == 'PATCH' && r.path == '/amenity-bookings/b1/approve',
      ),
      isTrue,
    );
    expect(find.text('Đã duyệt'), findsOneWidget);
  });

  testWidgets('ban quản lý hủy lượt đã xác nhận do sự cố (bắt buộc lý do)', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    final adapter = await _open(
      tester,
      '/bookings/b1',
      role: 'staff',
      department: 'facility',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/amenity-bookings/b1') => okJson(
          _booking(status: 'confirmed', actions: ['cancel-by-staff']),
        ),
        ('PATCH', '/amenity-bookings/b1/cancel-by-staff') => () {
          sent = req.data as Map<String, dynamic>;
          return okJson({
            ..._booking(status: 'cancelled'),
            'cancelReason': 'Bảo trì',
            'cancelledByStaff': true,
          });
        }(),
        _ => null,
      },
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Hủy do sự cố'));
    await tester.pumpAndSettle();
    // Bỏ trống lý do: không gửi
    await tester.tap(find.widgetWithText(FilledButton, 'Hủy lượt đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Tối thiểu 3 ký tự'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'PATCH'), isEmpty);

    await tester.enterText(find.byType(TextFormField), 'Bảo trì');
    await tester.tap(find.widgetWithText(FilledButton, 'Hủy lượt đặt'));
    await tester.pumpAndSettle();
    expect(sent, {'reason': 'Bảo trì'});
    expect(find.text('Đã hủy và báo cho cư dân'), findsOneWidget);
  });

  testWidgets(
    'lượt chờ duyệt: Facility chỉ thấy Từ chối, không thấy Hủy do sự cố',
    (tester) async {
      await _open(
        tester,
        '/bookings/b1',
        role: 'staff',
        department: 'facility',
        handler: (req) => req.path == '/amenity-bookings/b1'
            ? okJson(
                _booking(actions: ['approve', 'reject', 'cancel-by-staff']),
              )
            : null,
      );
      expect(find.text('Từ chối'), findsOneWidget);
      expect(find.text('Hủy do sự cố'), findsNothing);
    },
  );

  testWidgets('người đặt hủy lượt đặt (lý do không bắt buộc)', (tester) async {
    final adapter = await _open(
      tester,
      '/bookings/b1',
      role: 'resident',
      handler: (req) => switch ((req.method, req.path)) {
        ('GET', '/amenity-bookings/b1') => okJson(
          _booking(status: 'confirmed', actions: ['cancel']),
        ),
        ('PATCH', '/amenity-bookings/b1/cancel') => okJson(
          _booking(status: 'cancelled'),
        ),
        _ => null,
      },
    );
    expect(find.text('Hủy trước'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Hủy lượt đặt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hủy lượt đặt'));
    await tester.pumpAndSettle();
    expect(
      adapter.requests.any(
        (r) => r.method == 'PATCH' && r.path == '/amenity-bookings/b1/cancel',
      ),
      isTrue,
    );
    expect(find.text('Đã hủy, chỗ đã được trả lại'), findsOneWidget);
  });
}
