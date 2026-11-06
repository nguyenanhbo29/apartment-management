import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/application/auth_controller.dart';
import '../auth/data/app_user.dart';
import '../communication/application/communication_providers.dart';
import '../communication/presentation/notification_bell.dart';

class _Feature {
  const _Feature(this.title, this.icon, this.route, this.visible);
  final String title;
  final IconData icon;
  final String route;
  final bool Function(AppUser user) visible;
}

bool _all(AppUser _) => true;
bool _manager(AppUser u) => u.isManager;
bool _resident(AppUser u) => u.isResident;
bool _residentViewer(AppUser u) => u.canViewResidents;

/// Danh sách chức năng theo vai trò. Mỗi module thêm mục vào đây khi hoàn thành.
const _features = <_Feature>[
  // M8
  _Feature('Bảng tin', Icons.campaign_outlined, '/announcements', _all),
  // M2
  _Feature('Căn hộ của tôi', Icons.home_outlined, '/my-apartments', _resident),
  _Feature('Căn hộ', Icons.apartment_outlined, '/apartments', _residentViewer),
  _Feature('Cư dân', Icons.groups_outlined, '/residents', _residentViewer),
  _Feature('Duyệt cư trú', Icons.how_to_reg_outlined, '/registrations', _manager),
  // M1
  _Feature('Tài khoản', Icons.manage_accounts_outlined, '/users', _manager),
  _Feature('Hồ sơ', Icons.person_outline, '/profile', _all),
];

/// Trang chủ: hiển thị chức năng đúng với vai trò người dùng.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    final theme = Theme.of(context);
    final items = _features.where((f) => f.visible(user)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý chung cư'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Hồ sơ',
            onPressed: () => context.push('/profile'),
            icon: CircleAvatar(radius: 16, child: Text(user.initials)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(unreadCountProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Xin chào, ${user.fullName}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              user.roleLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final f in items)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await context.push(f.route);
                        // Thao tác trong module có thể sinh thông báo mới
                        ref.invalidate(unreadCountProvider);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(f.icon, size: 32, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(f.title, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
