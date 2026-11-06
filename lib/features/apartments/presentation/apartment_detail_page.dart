import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';
import '../application/apartments_providers.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';
import 'widgets.dart';

/// UC-07 (thông tin căn hộ) + UC-12 (thành viên).
/// - Quản lý: thêm/sửa cư dân, đổi người nộp phí, ghi nhận chuyển đi, xem lịch sử.
/// - Kế toán, Lễ tân: chỉ xem.
/// - Cư dân: xem căn mình ở; chủ hộ được khai báo thành viên và theo dõi đơn.
class ApartmentDetailPage extends ConsumerWidget {
  const ApartmentDetailPage({super.key, required this.apartmentId});

  final String apartmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(apartmentDetailProvider(apartmentId));
    final user = ref.watch(currentUserProvider)!;

    return detail.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(apartmentDetailProvider(apartmentId)),
        ),
      ),
      data: (apt) => _DetailView(apartment: apt, user: user),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.statuses, this.emptyText);
  final String label;
  final List<ResidentStatus> statuses;
  final String emptyText;
}

class _DetailView extends ConsumerWidget {
  const _DetailView({required this.apartment, required this.user});

  final Apartment apartment;
  final AppUser user;

  List<_Tab> get _tabs {
    const current = _Tab('Đang ở', [ResidentStatus.active], 'Chưa có người cư trú');
    if (user.canViewResidents) {
      return const [
        current,
        _Tab('Đơn khai báo', [ResidentStatus.pending, ResidentStatus.rejected], 'Không có đơn'),
        _Tab('Lịch sử', [ResidentStatus.ended], 'Chưa có ai chuyển đi'),
      ];
    }
    if (apartment.myMembership?.isOwner ?? false) {
      return const [
        current,
        _Tab('Đơn khai báo', [ResidentStatus.pending, ResidentStatus.rejected], 'Chưa gửi đơn nào'),
      ];
    }
    return const [current];
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Xóa căn hộ',
      message: 'Chỉ xóa được căn hộ chưa từng có hồ sơ cư trú. Xóa căn ${apartment.code}?',
      confirmText: 'Xóa',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apartmentsRepositoryProvider).deleteApartment(apartment.id);
      invalidateApartmentData(ref);
      if (context.mounted) {
        showSnack(context, 'Đã xóa căn hộ');
        context.pop(true);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = _tabs;
    final isOwner = apartment.myMembership?.isOwner ?? false;

    Widget? fab;
    if (user.isManager) {
      fab = FloatingActionButton.extended(
        onPressed: () => context.push('/apartments/${apartment.id}/residents/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Thêm cư dân'),
      );
    } else if (isOwner) {
      fab = FloatingActionButton.extended(
        onPressed: () => context.push('/apartments/${apartment.id}/register'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Khai báo thành viên'),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        floatingActionButton: fab,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              title: Text('Căn ${apartment.code}'),
              actions: [
                if (user.isManager)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') context.push('/apartments/${apartment.id}/edit');
                      if (v == 'delete') _delete(context, ref);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Sửa thông tin căn hộ')),
                      PopupMenuItem(value: 'delete', child: Text('Xóa căn hộ')),
                    ],
                  ),
              ],
              bottom: tabs.length > 1
                  ? TabBar(tabs: [for (final t in tabs) Tab(text: t.label)])
                  : null,
            ),
            SliverToBoxAdapter(child: _InfoCard(apartment: apartment)),
          ],
          body: TabBarView(
            children: [
              for (final t in tabs)
                _ResidentsTab(apartment: apartment, tab: t, canManage: user.isManager),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.apartment});
  final Apartment apartment;

  @override
  Widget build(BuildContext context) {
    final a = apartment;
    final m = a.myMembership;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tầng ${a.floor} · ${formatArea(a.area)}'
                    '${a.bedrooms != null ? ' · ${a.bedrooms} phòng ngủ' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge.apartment(context, a.status),
              ],
            ),
            const SizedBox(height: 8),
            InfoRow(icon: Icons.home_outlined, label: 'Chủ hộ', value: a.ownerName ?? 'Chưa có'),
            InfoRow(
              icon: Icons.groups_outlined,
              label: 'Đang cư trú',
              value: '${a.residentCount} người',
            ),
            if (m != null)
              InfoRow(
                icon: Icons.badge_outlined,
                label: 'Bạn là',
                value: '${m.relation.label}${m.isPayer ? ' · Người nộp phí' : ''}',
              ),
            if (a.note != null) InfoRow(icon: Icons.notes, label: 'Ghi chú', value: a.note!),
          ],
        ),
      ),
    );
  }
}

class _ResidentsTab extends ConsumerWidget {
  const _ResidentsTab({required this.apartment, required this.tab, required this.canManage});

  final Apartment apartment;
  final _Tab tab;
  final bool canManage;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(ApartmentsRepository repo) action,
    String done,
  ) async {
    try {
      await action(ref.read(apartmentsRepositoryProvider));
      invalidateApartmentData(ref);
      if (context.mounted) showSnack(context, done);
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _moveOut(BuildContext context, WidgetRef ref, ResidentRecord r) async {
    final result = await showDialog<(DateTime, String)>(
      context: context,
      builder: (_) => _MoveOutDialog(record: r),
    );
    if (result == null || !context.mounted) return;
    await _act(
      context,
      ref,
      (repo) => repo.moveOut(r.id, date: result.$1, reason: result.$2),
      'Đã ghi nhận ${r.fullName} chuyển đi',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = residentsQuery(apartment.id, tab.statuses);
    final list = ref.watch(apartmentResidentsProvider(query));

    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(apartmentResidentsProvider(query))),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(apartmentResidentsProvider(query).future),
        child: items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 48),
                  Center(child: Text(tab.emptyText)),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = items[i];
                  final actionable = canManage && r.status == ResidentStatus.active;
                  return ResidentTile(
                    record: r,
                    trailing: actionable
                        ? PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'edit':
                                  context.push('/residents/${r.id}/edit');
                                case 'payer':
                                  _act(
                                    context,
                                    ref,
                                    (repo) => repo.setPayer(r.id),
                                    '${r.fullName} là người nộp phí',
                                  );
                                case 'move-out':
                                  _moveOut(context, ref, r);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Sửa hồ sơ')),
                              if (!r.isPayer)
                                const PopupMenuItem(
                                  value: 'payer',
                                  child: Text('Đặt làm người nộp phí'),
                                ),
                              const PopupMenuItem(
                                value: 'move-out',
                                child: Text('Ghi nhận chuyển đi'),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }
}

/// UC-11: hộp thoại ghi nhận chuyển đi.
class _MoveOutDialog extends StatefulWidget {
  const _MoveOutDialog({required this.record});
  final ResidentRecord record;

  @override
  State<_MoveOutDialog> createState() => _MoveOutDialogState();
}

class _MoveOutDialogState extends State<_MoveOutDialog> {
  DateTime _date = DateTime.now();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.record.fullName} chuyển đi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DateField(
            label: 'Ngày chuyển đi',
            value: _date,
            clearable: false,
            firstDate: widget.record.moveInDate,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Lý do (không bắt buộc)'),
          ),
          const SizedBox(height: 12),
          Text(
            'Hồ sơ được giữ trong lịch sử, tài khoản ứng dụng (nếu có) không bị xóa.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_date, _reason.text)),
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}
