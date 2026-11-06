import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/apartments/presentation/apartment_detail_page.dart';
import '../../features/apartments/presentation/apartment_form_page.dart';
import '../../features/apartments/presentation/apartment_list_page.dart';
import '../../features/apartments/presentation/my_apartments_page.dart';
import '../../features/apartments/presentation/registrations_page.dart';
import '../../features/apartments/presentation/resident_form_page.dart';
import '../../features/apartments/presentation/resident_search_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/app_user.dart';
import '../../features/auth/presentation/change_password_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/communication/presentation/announcement_detail_page.dart';
import '../../features/communication/presentation/announcement_form_page.dart';
import '../../features/communication/presentation/announcements_page.dart';
import '../../features/communication/presentation/notifications_page.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/users/presentation/user_detail_page.dart';
import '../../features/users/presentation/user_form_page.dart';
import '../../features/users/presentation/user_list_page.dart';

const _publicRoutes = {'/login', '/forgot-password'};

bool _manager(AppUser u) => u.isManager;
bool _residentViewer(AppUser u) => u.canViewResidents;
bool _resident(AppUser u) => u.isResident;

/// Luật phân quyền route: luật khớp ĐẦU TIÊN quyết định. Đặt luật cụ thể lên trước.
/// Backend vẫn kiểm tra quyền trên mọi API; đây chỉ để không mở màn hình sai vai trò.
final _routeRules = <(RegExp, bool Function(AppUser))>[
  (RegExp(r'^/users'), _manager),
  (RegExp(r'^/apartments/new$'), _manager),
  (RegExp(r'^/apartments/[^/]+/(edit|residents/new)$'), _manager),
  (RegExp(r'^/apartments/[^/]+/register$'), _resident),
  // Chi tiết căn hộ: cư dân xem căn mình ở (backend kiểm tra thành viên)
  (RegExp(r'^/apartments/[^/]+$'), (u) => u.canViewResidents || u.isResident),
  (RegExp(r'^/apartments$'), _residentViewer),
  (RegExp(r'^/residents/[^/]+/edit$'), _manager),
  (RegExp(r'^/residents'), _residentViewer),
  (RegExp(r'^/registrations'), _manager),
  (RegExp(r'^/my-apartments'), _resident),
  (RegExp(r'^/announcements/new$'), _manager),
  // /announcements, /announcements/:id, /notifications: mọi vai trò
];

/// Quyết định chuyển hướng theo trạng thái đăng nhập và vai trò.
@visibleForTesting
String? authRedirect(AsyncValue<AppUser?> auth, String location) {
  if (auth.isLoading || auth.hasError) return location == '/splash' ? null : '/splash';

  final user = auth.value;
  if (user == null) return _publicRoutes.contains(location) ? null : '/login';

  if (user.mustChangePassword) {
    return location == '/change-password' ? null : '/change-password';
  }
  if (_publicRoutes.contains(location) || location == '/splash') return '/';

  for (final (pattern, allowed) in _routeRules) {
    if (pattern.hasMatch(location)) return allowed(user) ? null : '/';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);

  String id(GoRouterState s) => s.pathParameters['id']!;

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(path: '/change-password', builder: (_, _) => const ChangePasswordPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),

      // M1
      GoRoute(
        path: '/users',
        builder: (_, _) => const UserListPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const UserFormPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => UserDetailPage(userId: id(s)),
          ),
        ],
      ),

      // M2
      GoRoute(
        path: '/apartments',
        builder: (_, _) => const ApartmentListPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const ApartmentFormPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => ApartmentDetailPage(apartmentId: id(s)),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, s) => ApartmentFormPage(apartmentId: id(s)),
              ),
              GoRoute(
                path: 'residents/new',
                builder: (_, s) =>
                    ResidentFormPage(mode: ResidentFormMode.create, apartmentId: id(s)),
              ),
              GoRoute(
                path: 'register',
                builder: (_, s) =>
                    ResidentFormPage(mode: ResidentFormMode.register, apartmentId: id(s)),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/residents',
        builder: (_, _) => const ResidentSearchPage(),
        routes: [
          GoRoute(
            path: ':id/edit',
            builder: (_, s) => ResidentFormPage(mode: ResidentFormMode.edit, residentId: id(s)),
          ),
        ],
      ),
      GoRoute(path: '/registrations', builder: (_, _) => const RegistrationsPage()),
      GoRoute(path: '/my-apartments', builder: (_, _) => const MyApartmentsPage()),

      // M8
      GoRoute(
        path: '/announcements',
        builder: (_, _) => const AnnouncementsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const AnnouncementFormPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => AnnouncementDetailPage(announcementId: id(s)),
          ),
        ],
      ),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsPage()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
