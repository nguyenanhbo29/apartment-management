import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/multipart.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../application/service_requests_providers.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';
import 'widgets.dart';

/// UC-29 → 34: Chi tiết phiếu + timeline + nút thao tác theo vai trò / trạng thái.
/// Nút chỉ để tiện; backend vẫn kiểm tra (allowedActions do backend tính).
class RequestDetailPage extends ConsumerStatefulWidget {
  const RequestDetailPage({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends ConsumerState<RequestDetailPage> {
  bool _busy = false;

  ServiceRequestsRepository get _repo =>
      ref.read(serviceRequestsRepositoryProvider);
  void _reload() => ref.invalidate(requestDetailProvider(widget.requestId));

  /// Chạy thao tác; 409 INVALID_STATE -> tải lại và báo "Phiếu đã thay đổi".
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, success);
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(
        context,
        e.code == 'INVALID_STATE' ? 'Phiếu đã thay đổi, đã tải lại' : e.message,
        error: true,
      );
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      _reload();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAction(RequestAction action, ServiceRequest r) async {
    final id = r.id;
    switch (action) {
      case RequestAction.assign:
      case RequestAction.reassign:
        final route = action == RequestAction.reassign
            ? '/requests/$id/assign?reassign=1'
            : '/requests/$id/assign';
        final done = await context.push<bool>(route);
        if (done == true) _reload();
      case RequestAction.reject:
        final reason = await reasonDialog(
          context,
          title: 'Từ chối phiếu',
          confirmText: 'Từ chối',
          destructive: true,
        );
        if (reason != null) {
          await _run(() => _repo.reject(id, reason), 'Đã từ chối phiếu');
        }
      case RequestAction.start:
        final ok = await confirmDialog(
          context,
          title: 'Bắt đầu xử lý',
          message: 'Xác nhận bắt đầu xử lý phiếu ${r.code}?',
        );
        if (ok) await _run(() => _repo.start(id), 'Đã chuyển sang đang xử lý');
      case RequestAction.finish:
        final result = await _finishSheet();
        if (result != null) {
          await _run(
            () => _repo.finish(id, result.$1, images: result.$2),
            'Đã báo hoàn thành, chờ cư dân nghiệm thu',
          );
        }
      case RequestAction.confirm:
        final result = await _confirmDialog();
        if (result != null) {
          await _run(
            () => _repo.confirm(id, result.$1, feedback: result.$2),
            'Cảm ơn bạn đã nghiệm thu',
          );
        }
      case RequestAction.reopen:
        final reason = await reasonDialog(
          context,
          title: 'Yêu cầu làm lại',
          label: 'Chưa đạt ở điểm nào?',
        );
        if (reason != null) {
          await _run(() => _repo.reopen(id, reason), 'Đã gửi yêu cầu làm lại');
        }
      case RequestAction.cancel:
        final reason = await reasonDialog(
          context,
          title: 'Rút phiếu ${r.code}?',
          label: 'Lý do (không bắt buộc)',
          confirmText: 'Rút phiếu',
          destructive: true,
          required: false,
        );
        if (reason != null) {
          await _run(
            () => _repo.cancel(id, reason: reason),
            r.status == RequestStatus.assigned
                ? 'Đã rút phiếu và báo nhân viên'
                : 'Đã rút phiếu',
          );
        }
    }
  }

  /// UC-33: ghi chú kết quả (bắt buộc) + ảnh sau xử lý (tùy chọn).
  Future<(String, List<UploadFile>)?> _finishSheet() {
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var images = <UploadFile>[];
    return showModalBottomSheet<(String, List<UploadFile>)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          // Chừa thanh điều hướng hệ thống (gesture bar) và bàn phím
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              16,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Báo hoàn thành', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Kết quả xử lý'),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Tối thiểu 3 ký tự' : null,
              ),
              const SizedBox(height: 12),
              ImagePickerField(onChanged: (f) => images = f),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, (note.text.trim(), images));
                  }
                },
                child: const Text('Gửi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// UC-34: chấm điểm 1–5 + nhận xét.
  Future<(int, String)?> _confirmDialog() {
    final feedback = TextEditingController();
    var rating = 5;
    return showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nghiệm thu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i sao',
                      onPressed: () => setLocal(() => rating = i),
                      icon: Icon(
                        i <= rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: feedback,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nhận xét (không bắt buộc)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (rating, feedback.text)),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(requestDetailProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.code ?? 'Chi tiết phiếu')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: _reload),
        data: (r) => RefreshIndicator(
          onRefresh: () =>
              ref.refresh(requestDetailProvider(widget.requestId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Header(r),
              const Divider(height: 32),
              _Info(r),
              if (r.images.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionTitle('Ảnh đính kèm'),
                NetworkImageStrip(r.images),
              ],
              if (r.resultNote != null || r.resultImages.isNotEmpty) ...[
                const Divider(height: 32),
                const _SectionTitle('Kết quả xử lý'),
                if (r.resultNote != null) Text(r.resultNote!),
                const SizedBox(height: 8),
                NetworkImageStrip(r.resultImages),
              ],
              if (r.rating != null) ...[
                const Divider(height: 32),
                const _SectionTitle('Đánh giá'),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                        i <= r.rating! ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                  ],
                ),
                if ((r.feedback ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(r.feedback!),
                  ),
              ],
              const Divider(height: 32),
              const _SectionTitle('Lịch sử xử lý'),
              _Timeline(r.timeline),
            ],
          ),
        ),
      ),
      bottomNavigationBar: switch (async.value) {
        final r? when r.allowedActions.isNotEmpty => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _busy
                ? const LinearProgressIndicator()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      for (final a in RequestAction.values.where(
                        r.allowedActions.contains,
                      ))
                        _isSecondary(a)
                            ? OutlinedButton(
                                onPressed: () => _onAction(a, r),
                                child: Text(a.label),
                              )
                            : FilledButton(
                                onPressed: () => _onAction(a, r),
                                child: Text(a.label),
                              ),
                    ],
                  ),
          ),
        ),
        _ => null,
      },
    );
  }

  bool _isSecondary(RequestAction a) =>
      a == RequestAction.reject ||
      a == RequestAction.reopen ||
      a == RequestAction.reassign ||
      a == RequestAction.cancel;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.r);
  final ServiceRequest r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            RequestStatusChip(r.status),
            if (r.isOverdue) overdueChip,
            if (r.autoClosed) const Text('(tự đóng)'),
          ],
        ),
        const SizedBox(height: 8),
        Text(r.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(r.description),
        if (r.rejectReason != null) ...[
          const SizedBox(height: 12),
          Text(
            'Lý do từ chối: ${r.rejectReason}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        if (r.status == RequestStatus.cancelled) ...[
          const SizedBox(height: 12),
          Text(
            r.cancelReason == null
                ? 'Cư dân đã rút phiếu'
                : 'Cư dân đã rút phiếu: ${r.cancelReason}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.r);
  final ServiceRequest r;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InfoRow(
          label: 'Loại',
          value: '${r.type.label} · ${r.category.label}',
          icon: Icons.category_outlined,
        ),
        InfoRow(
          label: 'Ưu tiên',
          value: r.priority.label,
          icon: Icons.flag_outlined,
        ),
        if (r.apartmentCode != null)
          InfoRow(
            label: 'Căn hộ',
            value: r.apartmentCode!,
            icon: Icons.home_outlined,
          ),
        if (r.createdByName != null)
          InfoRow(
            label: 'Người gửi',
            value: r.createdByName!,
            icon: Icons.person_outline,
          ),
        InfoRow(
          label: 'Ngày gửi',
          value: formatDateTime(r.createdAt),
          icon: Icons.event_outlined,
        ),
        if (r.assignedStaffName != null)
          InfoRow(
            label: 'Người xử lý',
            value: [
              r.assignedStaffName!,
              if (r.department != null) r.department!.label,
              if (r.assignedStaffPhone != null) r.assignedStaffPhone!,
            ].join(' · '),
            icon: Icons.engineering_outlined,
          ),
        if (r.deadline != null)
          InfoRow(
            label: 'Hạn xử lý',
            value: formatDateTime(r.deadline),
            icon: Icons.schedule,
          ),
        if (r.closedAt != null)
          InfoRow(
            label: 'Đóng lúc',
            value: formatDateTime(r.closedAt),
            icon: Icons.task_alt,
          ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.entries);
  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) return const Text('Chưa có lịch sử');
    return Column(
      children: [
        for (final (i, h) in entries.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                    if (i < entries.length - 1)
                      Expanded(
                        child: VerticalDivider(
                          width: 12,
                          thickness: 2,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.label, style: theme.textTheme.titleSmall),
                        Text(
                          [
                            h.actorName ?? 'Hệ thống',
                            formatDateTime(h.createdAt),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (h.assignedStaffName != null)
                          Text(
                            'Giao cho ${h.assignedStaffName}${h.deadline != null ? ' · hạn ${formatDateTime(h.deadline)}' : ''}',
                          ),
                        if ((h.note ?? '').isNotEmpty) Text(h.note!),
                        if (h.attachments.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          NetworkImageStrip(h.attachments),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
