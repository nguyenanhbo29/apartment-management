import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
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

Map<String, dynamic> _apt({Map<String, dynamic>? membership}) => {
  '_id': 'a1',
  'code': 'A-101',
  'floor': 1,
  'area': 72.5,
  'status': 'occupied',
  'residentCount': 2,
  'ownerName': 'Chủ Hộ',
  'myMembership': membership,
};

Map<String, dynamic> _rec(
  String id,
  String name,
  String relation,
  String status, {
  String? reason,
}) => {
  '_id': id,
  'apartmentId': {'_id': 'a1', 'code': 'A-101'},
  'fullName': name,
  'relation': relation,
  'status': status,
  'isPayer': relation == 'owner',
  'rejectReason': reason,
  'source': 'registration',
  'registeredBy': {'_id': 'o1', 'fullName': 'Chủ Hộ'},
  'createdAt': '2026-11-01T03:00:00.000Z',
};

FakeAdapter _residentApi({required String relation}) => FakeAdapter((req) {
  final membership = {'id': 'm1', 'relation': relation, 'isPayer': relation == 'owner'};
  switch (req.path) {
    case '/users/me':
      return okJson(userJson(fullName: 'Tôi'));
    case '/apartments/mine':
      return okJson([_apt(membership: membership)]);
    case '/apartments/a1':
      return okJson(_apt(membership: membership));
    case '/apartments/a1/residents':
      final status = req.queryParameters['status'] as String;
      if (status.contains('pending')) {
        return okJson([
          _rec('r3', 'Người Thuê', 'tenant', 'pending'),
          _rec('r4', 'Bị Loại', 'member', 'rejected', reason: 'Thiếu giấy tờ'),
        ]);
      }
      return okJson([
        _rec('r1', 'Chủ Hộ', 'owner', 'active'),
        _rec('r2', 'Bé Na', 'member', 'active'),
      ]);
  }
  return okJson(null);
});

void main() {
  group('phân quyền route M2', () {
    test('Lễ tân/Kế toán xem căn hộ; Bảo vệ thì không', () {
      final reception = AsyncData<AppUser?>(_u(UserRole.staff, Department.reception));
      final security = AsyncData<AppUser?>(_u(UserRole.staff, Department.security));
      final accountant = AsyncData<AppUser?>(_u(UserRole.accountant));
      expect(authRedirect(reception, '/apartments'), isNull);
      expect(authRedirect(accountant, '/residents'), isNull);
      expect(authRedirect(security, '/apartments'), '/');
      expect(authRedirect(reception, '/apartments/new'), '/');
      expect(authRedirect(reception, '/registrations'), '/');
    });

    test('Cư dân chỉ vào căn của mình và form khai báo', () {
      final resident = AsyncData<AppUser?>(_u(UserRole.resident));
      expect(authRedirect(resident, '/my-apartments'), isNull);
      expect(authRedirect(resident, '/apartments/a1'), isNull);
      expect(authRedirect(resident, '/apartments/a1/register'), isNull);
      expect(authRedirect(resident, '/apartments'), '/');
      expect(authRedirect(resident, '/apartments/a1/edit'), '/');
      expect(authRedirect(resident, '/apartments/a1/residents/new'), '/');
      expect(authRedirect(resident, '/residents'), '/');
    });

    test('Quản lý không vào form khai báo của cư dân', () {
      final manager = AsyncData<AppUser?>(_u(UserRole.manager));
      expect(authRedirect(manager, '/apartments/a1/register'), '/');
      expect(authRedirect(manager, '/apartments/a1/residents/new'), isNull);
      expect(authRedirect(manager, '/my-apartments'), '/');
    });
  });

  testWidgets('chủ hộ: thấy thành viên, nút khai báo và đơn đã gửi', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        adapter: _residentApi(relation: 'owner'),
        tokens: MemoryTokenStorage('t'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Căn hộ của tôi'));
    await tester.pumpAndSettle();

    expect(find.text('Căn A-101'), findsOneWidget);
    expect(find.text('Bé Na'), findsOneWidget);
    expect(find.textContaining('Chủ hộ · Người nộp phí'), findsOneWidget);
    expect(find.text('Khai báo thành viên'), findsOneWidget);

    await tester.tap(find.text('Đơn khai báo'));
    await tester.pumpAndSettle();
    expect(find.text('Người Thuê'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.textContaining('Thiếu giấy tờ'), findsOneWidget);
  });

  testWidgets('thành viên: chỉ xem, không khai báo được', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        adapter: _residentApi(relation: 'member'),
        tokens: MemoryTokenStorage('t'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Căn hộ của tôi'));
    await tester.pumpAndSettle();

    expect(find.text('Bé Na'), findsOneWidget);
    expect(find.text('Khai báo thành viên'), findsNothing);
    expect(find.text('Đơn khai báo'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('Quản lý duyệt đơn đăng ký cư trú', (tester) async {
    var approved = false;
    final adapter = FakeAdapter((req) {
      if (req.path == '/users/me') return okJson(userJson(role: 'manager', fullName: 'QL'));
      if (req.path == '/residents/r3/approve') {
        approved = true;
        return okJson(_rec('r3', 'Người Thuê', 'tenant', 'active'));
      }
      if (req.path == '/residents/registrations') {
        final status = req.queryParameters['status'];
        final items = status == 'pending' && !approved
            ? [_rec('r3', 'Người Thuê', 'tenant', 'pending')]
            : <Map<String, dynamic>>[];
        return okJson(items, {'page': 1, 'limit': 30, 'total': items.length});
      }
      return okJson(null);
    });
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Duyệt cư trú'));
    await tester.pumpAndSettle();
    expect(find.text('Người Thuê · Người thuê'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ghi nhận Người Thuê'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt').last);
    await tester.pumpAndSettle();

    expect(approved, isTrue);
    expect(find.text('Không có đơn chờ duyệt'), findsOneWidget);
  });
}
