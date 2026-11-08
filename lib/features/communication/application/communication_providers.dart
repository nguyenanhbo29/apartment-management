import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';
import '../data/communication_repository.dart';
import '../data/models.dart';

/// Số thông báo chưa đọc (badge chuông). Làm mới bằng ref.invalidate.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  // Đổi tài khoản -> tải lại
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  return ref.watch(communicationRepositoryProvider).unreadCount();
});

final announcementDetailProvider = FutureProvider.autoDispose.family<Announcement, String>(
  (ref, id) => ref.watch(communicationRepositoryProvider).getAnnouncement(id),
);

/// Màn hình cần mở khi chạm vào thông báo (null nếu không có trang tương ứng
/// hoặc người nhận không có quyền mở).
String? routeForNotification(AppNotification n, AppUser user) {
  final id = n.linkId;
  return switch (n.linkKind) {
    'announcement' when id != null => '/announcements/$id',
    'apartment' when id != null => '/apartments/$id',
    'resident_registration' when user.isManager => '/registrations',
    // Module vận hành (Người 2)
    'service_request' when id != null => '/requests/$id',
    'vehicle' when id != null => '/vehicles/$id',
    'visitor' when id != null => '/visitors/$id',
    _ => null,
  };
}
