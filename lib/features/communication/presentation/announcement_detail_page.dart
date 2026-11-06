import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../application/communication_providers.dart';
import '../data/communication_repository.dart';
import '../data/models.dart';

/// UC-44: Chi tiết bảng tin. Quản lý: ghim/bỏ ghim, gỡ tin.
class AnnouncementDetailPage extends ConsumerWidget {
  const AnnouncementDetailPage({super.key, required this.announcementId});

  final String announcementId;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(CommunicationRepository repo) action,
    String done,
  ) async {
    try {
      await action(ref.read(communicationRepositoryProvider));
      ref.invalidate(announcementDetailProvider(announcementId));
      if (context.mounted) showSnack(context, done);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Gỡ bảng tin',
      message: 'Tin sẽ bị ẩn với mọi người nhận. Thao tác không hoàn tác được.',
      confirmText: 'Gỡ tin',
      destructive: true,
    );
    if (ok && context.mounted) {
      await _run(context, ref, (r) => r.remove(announcementId), 'Đã gỡ bảng tin');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(announcementDetailProvider(announcementId));
    final isManager = ref.watch(currentUserProvider)?.isManager ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng tin'),
        actions: [
          if (isManager && detail.value != null && !detail.value!.removed) ...[
            IconButton(
              tooltip: detail.value!.isPinned ? 'Bỏ ghim' : 'Ghim lên đầu',
              icon: Icon(detail.value!.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                final pin = !detail.value!.isPinned;
                _run(
                  context,
                  ref,
                  (r) => r.setPinned(announcementId, pin),
                  pin ? 'Đã ghim tin' : 'Đã bỏ ghim',
                );
              },
            ),
            IconButton(
              tooltip: 'Gỡ tin',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _remove(context, ref),
            ),
          ],
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(announcementDetailProvider(announcementId)),
        ),
        data: (Announcement a) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (a.removed || a.expired)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    a.removed ? 'Tin này đã được gỡ.' : 'Tin này đã hết hạn hiển thị.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            Text(a.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              [
                if (a.isPinned) 'Đã ghim',
                formatDateTime(a.publishedAt),
                if (a.createdByName != null) a.createdByName!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 32),
            SelectableText(a.content, style: theme.textTheme.bodyLarge),
            if (isManager) ...[
              const Divider(height: 32),
              InfoRow(label: 'Gửi tới', value: a.audience.label),
              InfoRow(label: 'Người nhận', value: '${a.recipientCount} người'),
              InfoRow(label: 'Hết hạn', value: formatDate(a.expiresAt, 'Không')),
            ],
          ],
        ),
      ),
    );
  }
}
