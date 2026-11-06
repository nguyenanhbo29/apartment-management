import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../apartments/presentation/widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/communication_repository.dart';
import '../data/models.dart';

/// UC-44: Bảng tin (mọi vai trò). Quản lý đăng tin mới và xem cả tin đã gỡ/hết hạn.
class AnnouncementsPage extends ConsumerStatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  ConsumerState<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends ConsumerState<AnnouncementsPage> {
  bool _includeInactive = false;
  int _reload = 0;

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final isManager = ref.watch(currentUserProvider)?.isManager ?? false;
    final repo = ref.watch(communicationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bảng tin')),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _open('/announcements/new'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Đăng tin'),
            )
          : null,
      body: Column(
        children: [
          if (isManager)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Hiện cả tin đã gỡ / hết hạn'),
                  selected: _includeInactive,
                  onSelected: (v) => setState(() => _includeInactive = v),
                ),
              ),
            ),
          Expanded(
            child: PagedListView<Announcement>(
              key: ValueKey('$_includeInactive|$_reload'),
              fetch: (page) =>
                  repo.listAnnouncements(page: page, includeInactive: _includeInactive),
              emptyText: 'Chưa có bảng tin nào',
              separated: false,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemBuilder: (context, a) => _AnnouncementCard(
                announcement: a,
                showMeta: isManager,
                onTap: () => _open('/announcements/${a.id}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, required this.showMeta, this.onTap});

  final Announcement announcement;
  final bool showMeta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: a.active ? 1 : 0.6,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (a.isPinned) ...[
                      Icon(Icons.push_pin, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        a.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (a.removed)
                      StatusBadge('Đã gỡ', color: theme.colorScheme.error)
                    else if (a.expired)
                      StatusBadge('Hết hạn', color: theme.colorScheme.outline),
                  ],
                ),
                const SizedBox(height: 6),
                Text(a.content, maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(
                  [
                    formatDateTime(a.publishedAt),
                    if (showMeta) 'Gửi: ${a.audience.label}',
                    if (showMeta) '${a.recipientCount} người nhận',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
