import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/amenities/presentation/amenity_pages.dart';
import '../../features/amenities/presentation/booking_pages.dart';
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
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/staff_report_page.dart';
import '../../features/communication/presentation/announcement_form_page.dart';
import '../../features/communication/presentation/announcements_page.dart';
import '../../features/communication/presentation/notifications_page.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/service_requests/presentation/assign_request_page.dart';
import '../../features/service_requests/presentation/my_requests_page.dart';
import '../../features/service_requests/presentation/request_detail_page.dart';
import '../../features/service_requests/presentation/request_form_page.dart';
import '../../features/service_requests/presentation/request_queue_page.dart';
import '../../features/staff/presentation/staff_list_page.dart';
import '../../features/tasks/presentation/task_pages.dart';
import '../../features/users/presentation/user_detail_page.dart';
import '../../features/users/presentation/user_form_page.dart';
import '../../features/users/presentation/user_list_page.dart';
import '../../features/vehicles/presentation/vehicle_pages.dart';
import '../../features/visitors/presentation/visitor_pages.dart';

const _publicRoutes = {'/login', '/forgot-password'};

bool _manager(AppUser u) => u.isManager;
bool _residentViewer(AppUser u) => u.canViewResidents;
bool _resident(AppUser u) => u.isResident;
bool _staffOf(AppUser u, Department d) => u.role == UserRole.staff && u.department == d;

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
  // Module vận hành (Người 2)
  (RegExp(r'^/staff'), _manager),
  // M5: /requests = phiếu của tôi (Resident); /requests/:id mọi vai trò (backend lọc phạm vi)
  (RegExp(r'^/requests$'), _resident),
  (RegExp(r'^/requests/new$'), _resident),
  (RegExp(r'^/requests/queue$'), _manager),
  (RegExp(r'^/requests/[^/]+/assign$'), _manager),
  (RegExp(r'^/assignments'), (u) => u.role == UserRole.staff),
  // M3: /vehicles, /visitors = của tôi (Resident); /:id mọi vai trò (backend lọc phạm vi)
  (RegExp(r'^/vehicles$'), _resident),
  (RegExp(r'^/vehicles/new$'), _resident),
  (
    RegExp(r'^/vehicles/manage$'),
    (u) => _staffOf(u, Department.security) || u.isManager || u.role == UserRole.accountant,
  ),
  (RegExp(r'^/visitors$'), _resident),
  (RegExp(r'^/visitors/new$'), _resident),
  (
    RegExp(r'^/visitors/gate$'),
    (u) =>
        _staffOf(u, Department.security) || _staffOf(u, Department.reception) || u.isManager,
  ),
  // M6: /amenities, /amenities/:id mọi vai trò; quản lý tiện ích chỉ Manager
  (RegExp(r'^/amenities/new$'), _manager),
  (RegExp(r'^/amenities/[^/]+/edit$'), _manager),
  (RegExp(r'^/bookings$'), _resident),
  (RegExp(r'^/bookings/queue$'), (u) => _staffOf(u, Department.facility) || u.isManager),
  // M7: Manager quản lý; Staff xem lịch sử / chi tiết nhiệm vụ của mình
  (RegExp(r'^/tasks/new$'), _manager),
  (RegExp(r'^/tasks/[^/]+/reassign$'), _manager),
  (RegExp(r'^/tasks'), (u) => u.isManager || u.role == UserRole.staff),
  // M9
  (RegExp(r'^/dashboard'), _manager),
  (RegExp(r'^/reports/staff'), _manager),
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

      // Module vận hành (Người 2) - UC-40
      GoRoute(path: '/staff', builder: (_, _) => const StaffListPage()),

      // M5 - Phiếu yêu cầu / phản ánh
      GoRoute(
        path: '/requests',
        builder: (_, _) => const MyRequestsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const RequestFormPage()),
          GoRoute(
            path: 'queue',
            builder: (_, s) => RequestQueuePage.fromQuery(s.uri.queryParameters),
          ),
          GoRoute(
            path: ':id',
            builder: (_, s) => RequestDetailPage(requestId: id(s)),
            routes: [
              GoRoute(
                path: 'assign',
                builder: (_, s) => AssignRequestPage(
                  requestId: id(s),
                  reassign: s.uri.queryParameters['reassign'] == '1',
                ),
              ),
            ],
          ),
        ],
      ),
      // UC-31: phiếu + nhiệm vụ (M7)
      GoRoute(path: '/assignments', builder: (_, _) => const MyWorkPage()),

      // M3 - Xe và khách
      GoRoute(
        path: '/vehicles',
        builder: (_, _) => const MyVehiclesPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const VehicleFormPage()),
          GoRoute(path: 'manage', builder: (_, _) => const VehiclesManagePage()),
          GoRoute(path: ':id', builder: (_, s) => VehicleDetailPage(vehicleId: id(s))),
        ],
      ),
      GoRoute(
        path: '/visitors',
        builder: (_, _) => const MyVisitorsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const VisitorFormPage()),
          GoRoute(path: 'gate', builder: (_, _) => const GateVisitorsPage()),
          GoRoute(path: ':id', builder: (_, s) => VisitorDetailPage(visitorId: id(s))),
        ],
      ),

      // M6 - Đặt tiện ích
      GoRoute(
        path: '/amenities',
        builder: (_, _) => const AmenitiesPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const AmenityFormPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => AmenityDetailPage(amenityId: id(s)),
            routes: [
              GoRoute(path: 'edit', builder: (_, s) => AmenityFormPage(amenityId: id(s))),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/bookings',
        builder: (_, _) => const MyBookingsPage(),
        routes: [
          GoRoute(path: 'queue', builder: (_, _) => const BookingQueuePage()),
          GoRoute(path: ':id', builder: (_, s) => BookingDetailPage(bookingId: id(s))),
        ],
      ),

      // M7 - Nhiệm vụ vận hành
      GoRoute(
        path: '/tasks',
        builder: (_, s) => TasksPage.fromQuery(s.uri.queryParameters),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const TaskFormPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => TaskDetailPage(taskId: id(s)),
            routes: [
              GoRoute(path: 'reassign', builder: (_, s) => TaskFormPage(taskId: id(s))),
            ],
          ),
        ],
      ),

      // M9 - Dashboard vận hành (UC-47), hiệu suất nhân viên (UC-48)
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(path: '/reports/staff', builder: (_, _) => const StaffReportPage()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
