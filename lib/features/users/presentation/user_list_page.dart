import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../application/users_providers.dart';

/// UC-04: Danh sách tài khoản (Manager).
class UserListPage extends ConsumerStatefulWidget {
  const UserListPage({super.key});

  @override
  ConsumerState<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends ConsumerState<UserListPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final filter = ref.read(userFilterProvider);
      ref.read(userFilterProvider.notifier).update(filter.copyWith(q: q));
    });
  }

  Future<void> _openCreate() async {
    final created = await context.push<bool>('/users/new');
    if (created == true) ref.invalidate(userListProvider);
  }

  Future<void> _openDetail(AppUser user) async {
    await context.push('/users/${user.id}');
    ref.invalidate(userListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(userFilterProvider);
    final list = ref.watch(userListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý tài khoản')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tạo tài khoản'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên, email, số điện thoại',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final r in UserRole.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(r.label),
                      selected: filter.role == r,
                      onSelected: (sel) => ref
                          .read(userFilterProvider.notifier)
                          .update(filter.copyWith(role: () => sel ? r : null)),
                    ),
                  ),
                FilterChip(
                  label: const Text('Đã khóa'),
                  selected: filter.status == UserStatus.inactive,
                  onSelected: (sel) => ref
                      .read(userFilterProvider.notifier)
                      .update(filter.copyWith(status: () => sel ? UserStatus.inactive : null)),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(userListProvider)),
              data: (state) {
                if (state.items.isEmpty) {
                  return const Center(child: Text('Không có tài khoản phù hợp'));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(userListProvider.future),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                        ref.read(userListProvider.notifier).loadMore().catchError((Object e) {
                          if (context.mounted) showSnack(context, errorMessage(e), error: true);
                        });
                      }
                      return false;
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: state.items.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i >= state.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final u = state.items[i];
                        return _UserTile(user: u, onTap: () => _openDetail(u));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});

  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text(user.initials)),
      title: Text(user.fullName),
      subtitle: Text('${user.email}\n${user.roleLabel}'),
      isThreeLine: true,
      trailing: user.isActive
          ? null
          : Tooltip(
              message: 'Đã khóa',
              child: Icon(Icons.lock_outline, color: theme.colorScheme.error),
            ),
    );
  }
}
