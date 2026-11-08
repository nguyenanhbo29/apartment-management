import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
import 'package:apartment_management/features/communication/application/communication_providers.dart';
import 'package:apartment_management/features/communication/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_api.dart';

AppUser _u(UserRole role) =>
    AppUser(id: 'x', email: 'x@t', fullName: 'X', role: role, status: UserStatus.active);

AppNotification _n(String? kind, [String? id]) => AppNotification(
  id: 'n',
  type: 't',
  title: 't',
  body: '',
  isRead: false,
  linkKind: kind,
  linkId: id,
);

Map<String, dynamic> _ann(String id, String title, {bool pinned = false}) => {
  '_id': id,
  'title': title,
  'content': 'Nội dung $title',
  'audience': {'type': 'all'},
  'isPinned': pinned,
  'status': 'published',
  'publishedAt': '2026-11-06T02:00:00.000Z',
  'recipientCount': 12,
};

void main() {
  group('điều hướng từ thông báo', () {
    test('mở đúng trang theo loại liên kết và quyền', () {
      final resident = _u(UserRole.resident);
      final manager = _u(UserRole.manager);
      expect(routeForNotification(_n('announcement', 'a1'), resident), '/announcements/a1');
      expect(routeForNotification(_n('apartment', 'p1'), resident), '/apartments/p1');
      expect(routeForNotification(_n('resident_registration', 'r1'), manager), '/registrations');
      expect(routeForNotification(_n('resident_registration', 'r1'), resident), isNull);
      expect(routeForNotification(_n(null), resident), isNull);
    });

    test('chỉ Quản lý vào form đăng tin', () {
      expect(authRedirect(AsyncData(_u(UserRole.resident)), '/announcements'), isNull);
      expect(authRedirect(AsyncData(_u(UserRole.resident)), '/announcements/new'), '/');
      expect(authRedirect(AsyncData(_u(UserRole.manager)), '/announcements/new'), isNull);
      expect(authRedirect(AsyncData(_u(UserRole.staff)), '/notifications'), isNull);
    });
  });

  testWidgets('badge chưa đọc, mở thông báo thì đánh dấu đã đọc', (tester) async {
    var unread = 2;
    final readCalls = <String>[];
    final adapter = FakeAdapter((req) {
      switch (req.path) {
        case '/users/me':
          return okJson(userJson());
        case '/notifications/unread-count':
          return okJson({'count': unread});
        case '/notifications':
          return okJson(
            [
              {
                '_id': 'n1',
                'type': 'resident_registration_approved',
                'title': 'Đăng ký cư trú đã được duyệt',
                'body': 'Bé Na đã được ghi nhận',
                'isRead': false,
                'createdAt': '2026-11-06T02:00:00.000Z',
              },
              {
                '_id': 'n2',
                'type': 'announcement',
                'title': 'Bảng tin: Cúp nước',
                'body': '',
                'isRead': true,
                'createdAt': '2026-11-05T02:00:00.000Z',
              },
            ],
            {'page': 1, 'limit': 30, 'total': 2, 'unread': unread},
          );
        case '/notifications/n1/read':
          readCalls.add('n1');
          unread--;
          return okJson({'_id': 'n1', 'isRead': true});
      }
      return okJson(null);
    });

    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')));
    await tester.pumpAndSettle();

    // Badge trên trang chủ
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Đăng ký cư trú đã được duyệt'), findsOneWidget);
    expect(find.text('Chưa đọc (2)'), findsOneWidget);

    await tester.tap(find.text('Đăng ký cư trú đã được duyệt'));
    await tester.pumpAndSettle();
    expect(readCalls, ['n1']);
    expect(find.text('Chưa đọc (1)'), findsOneWidget);
  });

  testWidgets('cư dân xem bảng tin, không có nút đăng tin', (tester) async {
    final adapter = FakeAdapter((req) {
      switch (req.path) {
        case '/users/me':
          return okJson(userJson());
        case '/notifications/unread-count':
          return okJson({'count': 0});
        case '/announcements':
          return okJson(
            [_ann('a1', 'Bảo trì thang máy', pinned: true), _ann('a2', 'Họp cư dân')],
            {'page': 1, 'limit': 20, 'total': 2},
          );
        case '/announcements/a2':
          return okJson(_ann('a2', 'Họp cư dân'));
      }
      return okJson(null);
    });

    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bảng tin'));
    await tester.pumpAndSettle();

    expect(find.text('Bảo trì thang máy'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('Đăng tin'), findsNothing);
    // Cư dân không thấy thông tin đối tượng / số người nhận
    expect(find.textContaining('người nhận'), findsNothing);

    await tester.tap(find.text('Họp cư dân'));
    await tester.pumpAndSettle();
    expect(find.text('Nội dung Họp cư dân'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('Quản lý đăng tin theo vai trò', (tester) async {
    Map<String, dynamic>? posted;
    final adapter = FakeAdapter((req) {
      switch (req.path) {
        case '/users/me':
          return okJson(userJson(role: 'manager', fullName: 'QL'));
        case '/notifications/unread-count':
          return okJson({'count': 0});
        case '/announcements':
          if (req.method == 'POST') {
            posted = req.data as Map<String, dynamic>;
            return (201, {'success': true, 'data': _ann('a9', 'Tin mới')});
          }
          return okJson(<Object>[], {'page': 1, 'limit': 20, 'total': 0});
      }
      return okJson(null);
    });

    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('t')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bảng tin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng tin'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Tập huấn PCCC');
    await tester.enterText(find.byType(TextFormField).at(1), 'Toàn bộ nhân viên tham dự');
    await tester.tap(find.text('Theo vai trò'));
    await tester.pumpAndSettle();

    // Chưa chọn vai trò -> báo lỗi, không gửi
    final submit = find.widgetWithText(FilledButton, 'Đăng tin');
    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Chọn ít nhất một vai trò'), findsOneWidget);
    expect(posted, isNull);

    await tester.tap(find.widgetWithText(FilterChip, 'Nhân viên'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng tin'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gửi tới: Nhân viên'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
    await tester.pumpAndSettle();

    expect(posted, isNotNull);
    expect(posted!['audience'], {
      'type': 'roles',
      'roles': ['staff'],
    });
    expect(posted!['title'], 'Tập huấn PCCC');
  });
}
