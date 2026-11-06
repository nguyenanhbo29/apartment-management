import 'package:apartment_management/core/router/app_router.dart';
import 'package:apartment_management/features/auth/data/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_api.dart';

AppUser _user({UserRole role = UserRole.resident, bool mustChange = false}) => AppUser(
  id: 'u1',
  email: 'a@test.local',
  fullName: 'A',
  role: role,
  status: UserStatus.active,
  mustChangePassword: mustChange,
);

void main() {
  group('authRedirect', () {
    test('đang khôi phục phiên -> splash', () {
      expect(authRedirect(const AsyncLoading(), '/'), '/splash');
      expect(authRedirect(const AsyncLoading(), '/splash'), isNull);
    });

    test('chưa đăng nhập -> login, trừ trang công khai', () {
      expect(authRedirect(const AsyncData(null), '/'), '/login');
      expect(authRedirect(const AsyncData(null), '/users'), '/login');
      expect(authRedirect(const AsyncData(null), '/forgot-password'), isNull);
    });

    test('bắt buộc đổi mật khẩu', () {
      final u = _user(mustChange: true);
      expect(authRedirect(AsyncData(u), '/'), '/change-password');
      expect(authRedirect(AsyncData(u), '/change-password'), isNull);
    });

    test('đã đăng nhập không quay lại login; chặn route theo vai trò', () {
      expect(authRedirect(AsyncData(_user()), '/login'), '/');
      expect(authRedirect(AsyncData(_user()), '/users'), '/');
      expect(authRedirect(AsyncData(_user()), '/users/abc'), '/');
      expect(authRedirect(AsyncData(_user(role: UserRole.manager)), '/users/abc'), isNull);
    });
  });

  testWidgets('chưa có token -> màn đăng nhập, không có đăng ký', (tester) async {
    final adapter = FakeAdapter((_) => okJson(null));
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage()));
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
    expect(find.textContaining('Đăng ký'), findsNothing);
  });

  testWidgets('đăng nhập sai hiện lỗi từ server', (tester) async {
    final adapter = FakeAdapter(
      (_) => errJson(401, 'INVALID_CREDENTIALS', 'Email hoặc mật khẩu không đúng'),
    );
    final tokens = MemoryTokenStorage();
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: tokens));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@test.local');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('Email hoặc mật khẩu không đúng'), findsOneWidget);
    expect(tokens.token, isNull);
  });

  testWidgets('cư dân đăng nhập -> trang chủ, không thấy Quản lý tài khoản', (tester) async {
    final adapter = FakeAdapter((req) {
      if (req.path == '/auth/login') {
        return okJson({'token': 'tok-1', 'user': userJson()});
      }
      return okJson(null);
    });
    final tokens = MemoryTokenStorage();
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: tokens));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'resident@test.local');
    await tester.enterText(find.byType(TextFormField).at(1), 'Passw0rd');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(tokens.token, 'tok-1');
    expect(find.text('Xin chào, Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Hồ sơ'), findsOneWidget);
    expect(find.text('Tài khoản'), findsNothing);
  });

  testWidgets('tài khoản mới cấp bị buộc đổi mật khẩu', (tester) async {
    final adapter = FakeAdapter((req) {
      if (req.path == '/users/me') return okJson(userJson(mustChangePassword: true));
      return okJson(null);
    });
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('tok')));
    await tester.pumpAndSettle();

    expect(find.text('Đổi mật khẩu'), findsWidgets);
    expect(find.textContaining('lần đăng nhập đầu tiên'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('token hết hạn khi mở app -> về đăng nhập, xóa token', (tester) async {
    final adapter = FakeAdapter((_) => errJson(401, 'UNAUTHORIZED', 'Token hết hạn'));
    final tokens = MemoryTokenStorage('expired');
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: tokens));
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(tokens.token, isNull);
  });

  testWidgets('Manager mở danh sách tài khoản', (tester) async {
    final adapter = FakeAdapter((req) {
      if (req.path == '/users/me') {
        return okJson(userJson(id: 'm1', role: 'manager', fullName: 'Quản lý'));
      }
      if (req.path == '/users') {
        return okJson(
          [
            userJson(id: 'u2', fullName: 'Trần Bảo Vệ', role: 'staff', department: 'security'),
            userJson(id: 'u3', fullName: 'Lê Cư Dân', status: 'inactive'),
          ],
          {'page': 1, 'limit': 20, 'total': 2, 'totalPages': 1},
        );
      }
      return okJson(null);
    });
    await tester.pumpWidget(buildTestApp(adapter: adapter, tokens: MemoryTokenStorage('tok')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tài khoản'));
    await tester.pumpAndSettle();

    expect(find.text('Quản lý tài khoản'), findsOneWidget);
    expect(find.text('Trần Bảo Vệ'), findsOneWidget);
    expect(find.textContaining('Nhân viên · Bảo vệ'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });
}
