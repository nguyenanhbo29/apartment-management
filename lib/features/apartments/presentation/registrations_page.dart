import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../application/apartments_providers.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';
import 'widgets.dart';

/// UC-10: Quản lý duyệt / từ chối đăng ký cư trú.
class RegistrationsPage extends ConsumerStatefulWidget {
  const RegistrationsPage({super.key});

  @override
  ConsumerState<RegistrationsPage> createState() => _RegistrationsPageState();
}

class _RegistrationsPageState extends ConsumerState<RegistrationsPage> {
  static const _tabs = [ResidentStatus.pending, ResidentStatus.active, ResidentStatus.rejected];
  int _reload = 0;

  Future<void> _approve(ResidentRecord r) async {
    final ok = await confirmDialog(
      context,
      title: 'Duyệt đăng ký',
      message:
          'Ghi nhận ${r.fullName} là ${r.relation.label.toLowerCase()} căn ${r.apartmentCode}?',
      confirmText: 'Duyệt',
    );
    if (!ok) return;
    await _run(() => ref.read(apartmentsRepositoryProvider).approve(r.id), 'Đã duyệt đăng ký');
  }

  Future<void> _reject(ResidentRecord r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null) return;
    await _run(
      () => ref.read(apartmentsRepositoryProvider).reject(r.id, reason),
      'Đã từ chối đăng ký',
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      invalidateApartmentData(ref);
      if (!mounted) return;
      setState(() => _reload++);
      showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(apartmentsRepositoryProvider);
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Duyệt đăng ký cư trú'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chờ duyệt'),
              Tab(text: 'Đã duyệt'),
              Tab(text: 'Đã từ chối'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final status in _tabs)
              PagedListView<ResidentRecord>(
                key: ValueKey('$status|$_reload'),
                fetch: (page) => repo.listRegistrations(status: status, page: page),
                emptyText: status == ResidentStatus.pending
                    ? 'Không có đơn chờ duyệt'
                    : 'Chưa có đơn nào',
                separated: false,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, r) => _RegistrationCard(
                  record: r,
                  onApprove: status == ResidentStatus.pending ? () => _approve(r) : null,
                  onReject: status == ResidentStatus.pending ? () => _reject(r) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({required this.record, this.onApprove, this.onReject});

  final ResidentRecord record;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.fullName} · ${r.relation.label}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                StatusBadge.resident(context, r.status),
              ],
            ),
            const SizedBox(height: 4),
            InfoRow(label: 'Căn hộ', value: r.apartmentCode ?? '—'),
            InfoRow(label: 'Người khai báo', value: r.registeredByName ?? '—'),
            InfoRow(label: 'Gửi lúc', value: formatDateTime(r.createdAt)),
            if (r.phone != null) InfoRow(label: 'Điện thoại', value: r.phone!),
            if (r.idNumber != null) InfoRow(label: 'CCCD', value: r.idNumber!),
            if (r.dateOfBirth != null)
              InfoRow(label: 'Ngày sinh', value: formatDate(r.dateOfBirth)),
            if (r.moveInDate != null)
              InfoRow(label: 'Ngày chuyển đến', value: formatDate(r.moveInDate)),
            if (r.note != null) InfoRow(label: 'Ghi chú', value: r.note!),
            if (r.rejectReason != null) InfoRow(label: 'Lý do từ chối', value: r.rejectReason!),
            if (onApprove != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: onReject, child: const Text('Từ chối')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: onApprove, child: const Text('Duyệt')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Từ chối đăng ký'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _reason,
          autofocus: true,
          maxLines: 3,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập lý do' : null,
          decoration: const InputDecoration(labelText: 'Lý do (gửi tới chủ hộ)'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _reason.text.trim());
          },
          child: const Text('Từ chối'),
        ),
      ],
    );
  }
}
