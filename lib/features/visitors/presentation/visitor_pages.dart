import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/media_widgets.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../apartments/application/apartments_providers.dart';
import '../../apartments/data/models.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';
import '../data/models.dart';
import '../data/visitors_repository.dart';

String _timeRange(Visitor v) {
  final from = v.timeFrom;
  final to = v.timeTo;
  if (from == null || to == null) return '';
  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${formatDate(from)} · ${hm(from)}–${hm(to)}';
}

const _overdueChip = StatusChip(
  label: 'Quá giờ hẹn',
  tone: StatusTone.danger,
  icon: Icons.schedule,
);

/// Một dòng lịch hẹn; [trailing] để màn cổng gắn nút Check-in / Check-out.
class VisitorTile extends StatelessWidget {
  const VisitorTile({
    super.key,
    required this.visitor,
    this.onTap,
    this.trailing,
  });

  final Visitor visitor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text('${v.numberOfPeople}')),
      title: Text(v.visitorName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              v.code,
              if (v.apartmentCode != null) 'Căn ${v.apartmentCode}',
              if ((v.visitorPhone ?? '').isNotEmpty) v.visitorPhone!,
            ].join(' · '),
          ),
          Text(_timeRange(v)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusChip(label: v.status.label, tone: v.status.tone),
              if (v.isOverdue) _overdueChip,
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: trailing,
    );
  }
}

Future<void> _runAction(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) showSnack(context, success);
  } on ApiException catch (e) {
    if (!context.mounted) return;
    final message = switch (e.code) {
      'INVALID_STATE' => 'Lịch hẹn đã thay đổi, đã tải lại',
      _ => e.message,
    };
    showSnack(context, message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, errorMessage(e), error: true);
  }
}

// ======================================================================== UC-16 Resident
class MyVisitorsPage extends ConsumerStatefulWidget {
  const MyVisitorsPage({super.key});

  @override
  ConsumerState<MyVisitorsPage> createState() => _MyVisitorsPageState();
}

class _MyVisitorsPageState extends ConsumerState<MyVisitorsPage> {
  int _reload = 0;

  Future<void> _open(String route) async {
    await context.push(route);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(visitorsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Khách của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/visitors/new'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Đăng ký khách'),
      ),
      body: PagedListView<Visitor>(
        key: ValueKey(_reload),
        fetch: (page) => repo.listMine(page: page),
        emptyText: 'Chưa có lịch hẹn khách',
        itemBuilder: (context, v) =>
            VisitorTile(visitor: v, onTap: () => _open('/visitors/${v.id}')),
      ),
    );
  }
}

class VisitorFormPage extends ConsumerStatefulWidget {
  const VisitorFormPage({super.key});

  @override
  ConsumerState<VisitorFormPage> createState() => _VisitorFormPageState();
}

class _VisitorFormPageState extends ConsumerState<VisitorFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _people = TextEditingController(text: '1');
  final _plate = TextEditingController();
  final _note = TextEditingController();
  String? _apartmentId;
  late DateTime _date;
  late TimeOfDay _from;
  late TimeOfDay _to;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Mặc định: hôm nay, từ nửa giờ tới, ở lại 2 tiếng
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 30 : 60,
    );
    final end = start.add(const Duration(hours: 2));
    _date = DateTime(start.year, start.month, start.day);
    _from = TimeOfDay.fromDateTime(start);
    _to = end.day == start.day
        ? TimeOfDay.fromDateTime(end)
        : const TimeOfDay(hour: 23, minute: 59);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _people, _plate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  String? get _timeError {
    if (!_at(_from).isBefore(_at(_to))) return 'Giờ đến phải trước giờ về';
    if (!_at(_to).isAfter(DateTime.now())) {
      return 'Không đăng ký lịch trong quá khứ';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool from) async {
    final t = await showTimePicker(
      context: context,
      initialTime: from ? _from : _to,
    );
    if (t != null) setState(() => from ? _from = t : _to = t);
  }

  Future<void> _submit(List<Apartment> apartments) async {
    final apartmentId =
        _apartmentId ?? (apartments.length == 1 ? apartments.first.id : null);
    if (!_formKey.currentState!.validate() || apartmentId == null) return;
    final err = _timeError;
    if (err != null) return showSnack(context, err, error: true);
    setState(() => _saving = true);
    try {
      final v = await ref
          .read(visitorsRepositoryProvider)
          .create(
            apartmentId: apartmentId,
            visitorName: _name.text,
            visitorPhone: _phone.text,
            numberOfPeople: int.parse(_people.text),
            visitDate: _date,
            timeFrom: _from,
            timeTo: _to,
            vehiclePlate: _plate.text,
            note: _note.text,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đã đăng ký khách'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gửi mã hẹn này cho khách để xuất trình tại cổng:'),
              const SizedBox(height: 12),
              SelectableText(
                v.code,
                style: Theme.of(ctx).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: v.code)),
              child: const Text('Sao chép'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Xong'),
            ),
          ],
        ),
      );
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apartments = ref.watch(myApartmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký khách')),
      body: apartments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(myApartmentsProvider),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Text('Bạn chưa được ghi nhận cư trú tại căn hộ nào.'),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (list.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _apartmentId,
                        decoration: const InputDecoration(labelText: 'Căn hộ'),
                        items: [
                          for (final a in list)
                            DropdownMenuItem(value: a.id, child: Text(a.code)),
                        ],
                        validator: (v) => v == null ? 'Chọn căn hộ' : null,
                        onChanged: (v) => setState(() => _apartmentId = v),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Tên khách'),
                      validator: (v) =>
                          (v ?? '').trim().length < 2 ? 'Nhập tên khách' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại khách (không bắt buộc)',
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        return s.isEmpty || RegExp(r'^\+?\d{9,15}$').hasMatch(s)
                            ? null
                            : 'Số điện thoại không hợp lệ';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _people,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Số người'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 50
                            ? 'Từ 1 đến 50 người'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Ngày đến'),
                      subtitle: Text(formatDate(_date)),
                      onTap: _pickDate,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.login),
                            title: const Text('Từ'),
                            subtitle: Text(_from.format(context)),
                            onTap: () => _pickTime(true),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.logout),
                            title: const Text('Đến'),
                            subtitle: Text(_to.format(context)),
                            onTap: () => _pickTime(false),
                          ),
                        ),
                      ],
                    ),
                    if (_timeError != null)
                      Text(
                        _timeError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _plate,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Biển số xe khách (không bắt buộc)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú (không bắt buộc)',
                      ),
                    ),
                    const SizedBox(height: 24),
                    LoadingButton(
                      loading: _saving,
                      onPressed: () => _submit(list),
                      label: 'Đăng ký',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ======================================================================== UC-17, 18 tại cổng
/// Khách tại cổng (Bảo vệ, Lễ tân, Manager). Mặc định hôm nay; tìm theo mã hẹn hoặc SĐT.
/// Chỉ Bảo vệ thấy nút Check-in / Check-out.
class GateVisitorsPage extends ConsumerStatefulWidget {
  const GateVisitorsPage({super.key});

  @override
  ConsumerState<GateVisitorsPage> createState() => _GateVisitorsPageState();
}

class _GateVisitorsPageState extends ConsumerState<GateVisitorsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  DateTime? _date; // null = hôm nay
  VisitorStatus? _status;
  int _reload = 0;
  final _busy = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => setState(() => _q = q.trim()),
    );
  }

  /// Có chữ cái -> mã hẹn (tự thêm 'VS-' nếu thiếu); toàn số -> SĐT.
  (String?, String?) get _codeOrPhone {
    if (_q.isEmpty) return (null, null);
    if (RegExp(r'[A-Za-z]').hasMatch(_q)) {
      final up = _q.toUpperCase();
      return (
        up.startsWith('VS-') ? up : 'VS-${up.replaceFirst(RegExp(r'^VS'), '')}',
        null,
      );
    }
    return (null, _q);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _act(Visitor v, bool checkIn) async {
    final repo = ref.read(visitorsRepositoryProvider);
    setState(() => _busy.add(v.id));
    await _runAction(
      context,
      () => checkIn ? repo.checkIn(v.id) : repo.checkOut(v.id),
      checkIn
          ? 'Đã check-in ${v.visitorName}'
          : 'Đã check-out ${v.visitorName}',
    );
    if (mounted) {
      setState(() {
        _busy.remove(v.id);
        _reload++;
      });
    }
  }

  Widget? _actionButton(Visitor v, bool isSecurity) {
    if (!isSecurity) return null;
    if (_busy.contains(v.id)) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // Theme chung đặt FilledButton rộng hết cỡ (Size.fromHeight) -> nút trong dòng phải tự giới hạn
    final style = FilledButton.styleFrom(minimumSize: const Size(104, 48));
    return switch (v.status) {
      VisitorStatus.expected => FilledButton(
        style: style,
        onPressed: () => _act(v, true),
        child: const Text('Check-in'),
      ),
      VisitorStatus.checkedIn => FilledButton.tonal(
        style: style,
        onPressed: () => _act(v, false),
        child: const Text('Check-out'),
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(visitorsRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    final isSecurity =
        user?.role == UserRole.staff && user?.department == Department.security;
    final (code, phone) = _codeOrPhone;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _date == null ? 'Khách hôm nay' : 'Khách ngày ${formatDate(_date)}',
        ),
        actions: [
          if (_date != null)
            TextButton(
              onPressed: () => setState(() => _date = null),
              child: const Text('Hôm nay'),
            ),
          IconButton(
            tooltip: 'Chọn ngày',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Mã hẹn (VS-...) hoặc số điện thoại',
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
                for (final s in <VisitorStatus?>[null, ...VisitorStatus.values])
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
            child: PagedListView<Visitor>(
              key: ValueKey(
                '$_q|${_date?.toIso8601String()}|${_status?.api}|$_reload',
              ),
              fetch: (page) => repo.gate(
                date: _date,
                code: code,
                phone: phone,
                status: _status,
                page: page,
              ),
              emptyText: 'Không có lịch hẹn',
              itemBuilder: (context, v) => VisitorTile(
                visitor: v,
                trailing: _actionButton(v, isSecurity),
                onTap: () async {
                  await context.push('/visitors/${v.id}');
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
class VisitorDetailPage extends ConsumerStatefulWidget {
  const VisitorDetailPage({super.key, required this.visitorId});
  final String visitorId;

  @override
  ConsumerState<VisitorDetailPage> createState() => _VisitorDetailPageState();
}

class _VisitorDetailPageState extends ConsumerState<VisitorDetailPage> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    await _runAction(context, action, success);
    ref.invalidate(visitorDetailProvider(widget.visitorId));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel(Visitor v) async {
    final reason = await reasonDialog(
      context,
      title: 'Hủy lịch hẹn',
      label: 'Lý do (không bắt buộc)',
      confirmText: 'Hủy lịch',
      destructive: true,
      required: false,
    );
    if (reason != null) {
      await _do(
        () => ref.read(visitorsRepositoryProvider).cancel(v.id, reason: reason),
        'Đã hủy lịch hẹn',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(visitorDetailProvider(widget.visitorId));
    final repo = ref.read(visitorsRepositoryProvider);
    final v = async.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch hẹn khách')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(visitorDetailProvider(widget.visitorId)),
        ),
        data: (v) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SelectableText(
                v.code,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Wrap(
                spacing: 6,
                children: [
                  StatusChip(label: v.status.label, tone: v.status.tone),
                  if (v.isOverdue) _overdueChip,
                ],
              ),
            ),
            const Divider(height: 32),
            InfoRow(
              label: 'Khách',
              value: '${v.visitorName} · ${v.numberOfPeople} người',
              icon: Icons.person_outline,
            ),
            if ((v.visitorPhone ?? '').isNotEmpty)
              InfoRow(
                label: 'Điện thoại',
                value: v.visitorPhone!,
                icon: Icons.phone_outlined,
              ),
            InfoRow(
              label: 'Thời gian',
              value: _timeRange(v),
              icon: Icons.schedule,
            ),
            if (v.apartmentCode != null)
              InfoRow(
                label: 'Căn hộ',
                value: v.apartmentCode!,
                icon: Icons.home_outlined,
              ),
            if (v.createdByName != null)
              InfoRow(
                label: 'Người hẹn',
                value: [
                  v.createdByName!,
                  if (v.createdByPhone != null) v.createdByPhone!,
                ].join(' · '),
                icon: Icons.badge_outlined,
              ),
            if ((v.vehiclePlate ?? '').isNotEmpty)
              InfoRow(
                label: 'Xe',
                value: v.vehiclePlate!,
                icon: Icons.directions_car_outlined,
              ),
            if ((v.note ?? '').isNotEmpty)
              InfoRow(label: 'Ghi chú', value: v.note!, icon: Icons.notes),
            if (v.checkInTime != null)
              InfoRow(
                label: 'Vào lúc',
                value: [
                  formatDateTime(v.checkInTime),
                  if (v.checkedInByName != null) v.checkedInByName!,
                ].join(' · '),
                icon: Icons.login,
              ),
            if (v.checkOutTime != null)
              InfoRow(
                label: 'Ra lúc',
                value: formatDateTime(v.checkOutTime),
                icon: Icons.logout,
              ),
            if ((v.cancelReason ?? '').isNotEmpty)
              InfoRow(
                label: 'Lý do hủy',
                value: v.cancelReason!,
                icon: Icons.info_outline,
              ),
          ],
        ),
      ),
      bottomNavigationBar: v == null || v.allowedActions.isEmpty
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
                          if (v.allowedActions.contains(VisitorAction.cancel))
                            OutlinedButton(
                              onPressed: () => _cancel(v),
                              child: const Text('Hủy lịch'),
                            ),
                          if (v.allowedActions.contains(VisitorAction.checkIn))
                            FilledButton(
                              onPressed: () =>
                                  _do(() => repo.checkIn(v.id), 'Đã check-in'),
                              child: const Text('Check-in'),
                            ),
                          if (v.allowedActions.contains(VisitorAction.checkOut))
                            FilledButton(
                              onPressed: () => _do(
                                () => repo.checkOut(v.id),
                                'Đã check-out',
                              ),
                              child: const Text('Check-out'),
                            ),
                        ],
                      ),
              ),
            ),
    );
  }
}
