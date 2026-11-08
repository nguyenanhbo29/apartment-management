import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/media_widgets.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/amenities_repository.dart';
import '../data/models.dart';

class BookingTile extends StatelessWidget {
  const BookingTile({
    super.key,
    required this.booking,
    this.onTap,
    this.showBooker = false,
  });

  final AmenityBooking booking;
  final VoidCallback? onTap;
  final bool showBooker;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(child: Icon(Icons.event_available_outlined)),
      title: Text(b.amenityName ?? 'Tiện ích'),
      subtitle: Text(
        [
          '${formatDate(b.startTime)} · ${b.timeLabel}',
          [
            '${b.numberOfParticipants} người',
            if (b.apartmentCode != null) 'Căn ${b.apartmentCode}',
            if (showBooker && b.bookedByName != null) b.bookedByName!,
          ].join(' · '),
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: StatusChip(label: b.status.label, tone: b.status.tone),
    );
  }
}

// ======================================================================== Resident
class MyBookingsPage extends ConsumerStatefulWidget {
  const MyBookingsPage({super.key});

  @override
  ConsumerState<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends ConsumerState<MyBookingsPage> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(amenitiesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch đặt của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/amenities');
          setState(() => _reload++);
        },
        icon: const Icon(Icons.add),
        label: const Text('Đặt tiện ích'),
      ),
      body: PagedListView<AmenityBooking>(
        key: ValueKey(_reload),
        fetch: (page) => repo.myBookings(page: page),
        emptyText: 'Chưa có lượt đặt nào',
        itemBuilder: (context, b) => BookingTile(
          booking: b,
          onTap: () async {
            await context.push('/bookings/${b.id}');
            setState(() => _reload++);
          },
        ),
      ),
    );
  }
}

// ======================================================================== UC-38 Facility / Manager
class BookingQueuePage extends ConsumerStatefulWidget {
  const BookingQueuePage({super.key});

  @override
  ConsumerState<BookingQueuePage> createState() => _BookingQueuePageState();
}

class _BookingQueuePageState extends ConsumerState<BookingQueuePage> {
  BookingStatus? _status = BookingStatus.pending;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(amenitiesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Duyệt đặt tiện ích')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in <BookingStatus?>[...BookingStatus.values, null])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s?.label ?? 'Tất cả'),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<AmenityBooking>(
              key: ValueKey('${_status?.name}|$_reload'),
              fetch: (page) => repo.queue(status: _status, page: page),
              emptyText: 'Không có lượt đặt',
              itemBuilder: (context, b) => BookingTile(
                booking: b,
                showBooker: true,
                onTap: () async {
                  await context.push('/bookings/${b.id}');
                  setState(() => _reload++);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================== Chi tiết
class BookingDetailPage extends ConsumerStatefulWidget {
  const BookingDetailPage({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends ConsumerState<BookingDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, success);
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(
          context,
          e.code == 'INVALID_STATE'
              ? 'Lượt đặt đã thay đổi, đã tải lại'
              : e.message,
          error: true,
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(AmenityBooking b) async {
    final ok = await confirmDialog(
      context,
      title: 'Duyệt lượt đặt',
      message: 'Duyệt lượt đặt ${b.amenityName}?',
      confirmText: 'Duyệt',
    );
    if (ok) {
      await _run(
        () => ref.read(amenitiesRepositoryProvider).approve(b.id),
        'Đã duyệt',
      );
    }
  }

  Future<void> _reject(AmenityBooking b) async {
    final reason = await reasonDialog(
      context,
      title: 'Từ chối lượt đặt',
      confirmText: 'Từ chối',
      destructive: true,
    );
    if (reason != null) {
      await _run(
        () => ref.read(amenitiesRepositoryProvider).reject(b.id, reason),
        'Đã từ chối',
      );
    }
  }

  Future<void> _cancel(AmenityBooking b) async {
    final reason = await reasonDialog(
      context,
      title: 'Hủy lượt đặt',
      label: 'Lý do (không bắt buộc)',
      confirmText: 'Hủy lượt đặt',
      destructive: true,
      required: false,
    );
    if (reason != null) {
      await _run(
        () =>
            ref.read(amenitiesRepositoryProvider).cancel(b.id, reason: reason),
        'Đã hủy, chỗ đã được trả lại',
      );
    }
  }

  /// Ban quản lý hủy khi có sự cố: bắt buộc lý do, không áp dụng hạn hủy.
  Future<void> _cancelByStaff(AmenityBooking b) async {
    final reason = await reasonDialog(
      context,
      title: 'Hủy do sự cố',
      label: 'Lý do (gửi cho cư dân)',
      confirmText: 'Hủy lượt đặt',
      destructive: true,
    );
    if (reason != null) {
      await _run(
        () => ref.read(amenitiesRepositoryProvider).cancelByStaff(b.id, reason),
        'Đã hủy và báo cho cư dân',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingDetailProvider(widget.bookingId));
    final b = async.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Lượt đặt tiện ích')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(bookingDetailProvider(widget.bookingId)),
        ),
        data: (b) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.amenityName ?? 'Tiện ích',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusChip(label: b.status.label, tone: b.status.tone),
              ],
            ),
            const SizedBox(height: 12),
            InfoRow(
              label: 'Thời gian',
              value: '${formatDate(b.startTime)} · ${b.timeLabel}',
              icon: Icons.schedule,
            ),
            if ((b.amenityLocation ?? '').isNotEmpty)
              InfoRow(
                label: 'Vị trí',
                value: b.amenityLocation!,
                icon: Icons.place_outlined,
              ),
            InfoRow(
              label: 'Số người',
              value: '${b.numberOfParticipants}',
              icon: Icons.groups_outlined,
            ),
            if (b.apartmentCode != null)
              InfoRow(
                label: 'Căn hộ',
                value: b.apartmentCode!,
                icon: Icons.home_outlined,
              ),
            if (b.bookedByName != null)
              InfoRow(
                label: 'Người đặt',
                value: [
                  b.bookedByName!,
                  if (b.bookedByPhone != null) b.bookedByPhone!,
                ].join(' · '),
                icon: Icons.person_outline,
              ),
            if ((b.note ?? '').isNotEmpty)
              InfoRow(label: 'Ghi chú', value: b.note!, icon: Icons.notes),
            if (b.cancelDeadline != null &&
                (b.status == BookingStatus.pending ||
                    b.status == BookingStatus.confirmed))
              InfoRow(
                label: 'Hủy trước',
                value: formatDateTime(b.cancelDeadline),
                icon: Icons.timer_outlined,
              ),
            if (b.reviewedByName != null)
              InfoRow(
                label: 'Người duyệt',
                value: b.reviewedByName!,
                icon: Icons.verified_outlined,
              ),
            if ((b.rejectReason ?? '').isNotEmpty)
              InfoRow(
                label: 'Lý do từ chối',
                value: b.rejectReason!,
                icon: Icons.info_outline,
              ),
            if ((b.cancelReason ?? '').isNotEmpty)
              InfoRow(
                label: b.cancelledByStaff ? 'Ban quản lý hủy' : 'Lý do hủy',
                value: b.cancelReason!,
                icon: Icons.info_outline,
              ),
          ],
        ),
      ),
      bottomNavigationBar: b == null || b.allowedActions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _busy
                    ? const LinearProgressIndicator()
                    : Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (b.allowedActions.contains('cancel'))
                            OutlinedButton(
                              onPressed: () => _cancel(b),
                              child: const Text('Hủy lượt đặt'),
                            ),
                          // Lượt chờ duyệt: Facility dùng "Từ chối"; nút hủy cho lượt
                          // đã xác nhận, hoặc Manager (không có quyền từ chối)
                          if (b.allowedActions.contains('cancel-by-staff') &&
                              !b.allowedActions.contains('reject'))
                            OutlinedButton(
                              onPressed: () => _cancelByStaff(b),
                              child: const Text('Hủy do sự cố'),
                            ),
                          if (b.allowedActions.contains('reject'))
                            OutlinedButton(
                              onPressed: () => _reject(b),
                              child: const Text('Từ chối'),
                            ),
                          if (b.allowedActions.contains('approve'))
                            FilledButton(
                              onPressed: () => _approve(b),
                              child: const Text('Duyệt'),
                            ),
                        ],
                      ),
              ),
            ),
    );
  }
}
