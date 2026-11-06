import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../auth/application/auth_controller.dart';
import '../application/communication_providers.dart';
import '../data/communication_repository.dart';
import '../data/models.dart';

/// UC-45, UC-46: Lịch sử thông báo, đánh dấu đã đọc.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _unreadOnly = false;
  int _reload = 0;
  // Đánh dấu đọc ngay trên giao diện, không cần tải lại cả danh sách
  final _readIds = <String>{};

  Future<void> _open(AppNotification n) async {
    final repo = ref.read(communicationRepositoryProvider);
    if (!n.isRead && !_readIds.contains(n.id)) {
      setState(() => _readIds.add(n.id));
      repo.markRead(n.id).then((_) => ref.invalidate(unreadCountProvider)).catchError((_) {});
    }
    final user = ref.read(currentUserProvider);
    final route = user == null ? null : routeForNotification(n, user);
    if (route != null && mounted) await context.push(route);
  }

  Future<void> _markAll() async {
    try {
      await ref.read(communicationRepositoryProvider).markAllRead();
      ref.invalidate(unreadCountProvider);
      if (!mounted) return;
      setState(() {
        _readIds.clear();
        _reload++;
      });
      showSnack(context, 'Đã đánh dấu tất cả là đã đọc');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(communicationRepositoryProvider);
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          TextButton(onPressed: unread > 0 ? _markAll : null, child: const Text('Đọc tất cả')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tất cả'),
                  selected: !_unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Chưa đọc${unread > 0 ? ' ($unread)' : ''}'),
                  selected: _unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<AppNotification>(
              key: ValueKey('$_unreadOnly|$_reload'),
              fetch: (page) => repo.listNotifications(page: page, unreadOnly: _unreadOnly),
              emptyText: _unreadOnly ? 'Không có thông báo chưa đọc' : 'Chưa có thông báo nào',
              itemBuilder: (context, n) {
                final isRead = n.isRead || _readIds.contains(n.id);
                return ListTile(
                  onTap: () => _open(n),
                  tileColor: isRead
                      ? null
                      : theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                  leading: CircleAvatar(
                    backgroundColor: isRead
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primaryContainer,
                    child: Icon(_iconFor(n.type), size: 20),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${n.body.isEmpty ? '' : '${n.body}\n'}${formatDateTime(n.createdAt)}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: n.body.isNotEmpty,
                  trailing: isRead
                      ? null
                      : Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    if (type == 'announcement') return Icons.campaign_outlined;
    if (type.startsWith('resident_')) return Icons.how_to_reg_outlined;
    if (type.startsWith('fee_') || type.startsWith('payment_')) return Icons.receipt_long_outlined;
    return Icons.notifications_outlined;
  }
}
