import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/app_user.dart';
import '../data/users_repository.dart';

class UserFilterNotifier extends Notifier<UserFilter> {
  @override
  UserFilter build() => const UserFilter();

  void update(UserFilter filter) => state = filter;
}

final userFilterProvider = NotifierProvider.autoDispose<UserFilterNotifier, UserFilter>(
  UserFilterNotifier.new,
);

class UserListState {
  const UserListState({
    required this.items,
    required this.total,
    required this.page,
    this.loadingMore = false,
  });

  final List<AppUser> items;
  final int total;
  final int page;
  final bool loadingMore;

  bool get hasMore => items.length < total;

  UserListState copyWith({bool? loadingMore}) => UserListState(
    items: items,
    total: total,
    page: page,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Danh sách tài khoản có lọc + tải thêm. Tự tải lại khi filter đổi.
class UserListController extends AsyncNotifier<UserListState> {
  @override
  Future<UserListState> build() => _fetch(1, const []);

  Future<UserListState> _fetch(int page, List<AppUser> previous) async {
    final filter = ref.watch(userFilterProvider);
    final res = await ref.read(usersRepositoryProvider).list(filter: filter, page: page);
    return UserListState(items: [...previous, ...res.items], total: res.total, page: res.page);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      state = AsyncData(await _fetch(current.page + 1, current.items));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

final userListProvider = AsyncNotifierProvider.autoDispose<UserListController, UserListState>(
  UserListController.new,
);

final userDetailProvider = FutureProvider.autoDispose.family<AppUser, String>(
  (ref, id) => ref.watch(usersRepositoryProvider).get(id),
);
