import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_chip.dart';
import '../../apartments/application/apartments_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/amenities_repository.dart';
import '../data/models.dart';

const _days = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

String _hoursLabel(Amenity a) =>
    '${a.openTime}–${a.closeTime} · ${a.slotDuration} phút/lượt · tối đa ${a.capacity} người';

// ======================================================================== UC-35 danh sách
class AmenitiesPage extends ConsumerWidget {
  const AmenitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(currentUserProvider)?.isManager ?? false;
    final async = ref.watch(amenityListProvider(isManager));
    return Scaffold(
      appBar: AppBar(title: const Text('Tiện ích')),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/amenities/new');
                ref.invalidate(amenityListProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Thêm tiện ích'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(amenityListProvider),
        ),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Chưa có tiện ích'))
            : RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(amenityListProvider(isManager).future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final a = list[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(a.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((a.location ?? '').isNotEmpty)
                              Text(a.location!),
                            Text(_hoursLabel(a)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (a.requiresApproval)
                                  const StatusChip(
                                    label: 'Cần duyệt',
                                    tone: StatusTone.warning,
                                  ),
                                if (!a.isActive)
                                  const StatusChip(
                                    label: 'Tạm ngưng',
                                    tone: StatusTone.danger,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await context.push('/amenities/${a.id}');
                          ref.invalidate(amenityListProvider);
                        },
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

// ======================================================================== UC-36, 37 chi tiết + đặt
class AmenityDetailPage extends ConsumerStatefulWidget {
  const AmenityDetailPage({super.key, required this.amenityId});
  final String amenityId;

  @override
  ConsumerState<AmenityDetailPage> createState() => _AmenityDetailPageState();
}

class _AmenityDetailPageState extends ConsumerState<AmenityDetailPage> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  (String, String) get _slotKey => (widget.amenityId, apiDate(_date));

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

  Future<void> _toggleActive(Amenity a) async {
    final ok = await confirmDialog(
      context,
      title: a.isActive ? 'Tạm ngưng tiện ích' : 'Mở lại tiện ích',
      message: a.isActive
          ? 'Cư dân sẽ không đặt mới được. Lượt đặt đã có giữ nguyên, ban quản lý tự xử lý.'
          : 'Cư dân có thể đặt lại tiện ích này.',
      destructive: a.isActive,
    );
    if (!ok) return;
    try {
      await ref.read(amenitiesRepositoryProvider).setActive(a.id, !a.isActive);
      ref.invalidate(amenityDetailProvider(a.id));
      ref.invalidate(amenitySlotsProvider);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  /// UC-37: chọn số người (+ căn hộ nếu ở nhiều căn), ghi chú → đặt.
  Future<void> _book(Amenity a, SlotInfo slot) async {
    final apartments = await ref.read(myApartmentsProvider.future);
    if (!mounted) return;
    if (apartments.isEmpty) {
      return showSnack(
        context,
        'Bạn chưa được ghi nhận cư trú tại căn hộ nào',
        error: true,
      );
    }
    final note = TextEditingController();
    var people = 1;
    var apartmentId = apartments.first.id;
    final maxPeople = slot.remaining < a.capacity ? slot.remaining : a.capacity;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Đặt ${a.name}', style: Theme.of(ctx).textTheme.titleLarge),
              Text(
                '${_days[_date.weekday % 7]}, ${formatDate(_date)} · ${slot.label}',
              ),
              const SizedBox(height: 16),
              if (apartments.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: apartmentId,
                  decoration: const InputDecoration(labelText: 'Căn hộ'),
                  items: [
                    for (final apt in apartments)
                      DropdownMenuItem(value: apt.id, child: Text(apt.code)),
                  ],
                  onChanged: (v) =>
                      setLocal(() => apartmentId = v ?? apartmentId),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  const Expanded(child: Text('Số người')),
                  IconButton(
                    tooltip: 'Bớt',
                    onPressed: people > 1
                        ? () => setLocal(() => people--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$people', style: Theme.of(ctx).textTheme.titleMedium),
                  IconButton(
                    tooltip: 'Thêm',
                    onPressed: people < maxPeople
                        ? () => setLocal(() => people++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (không bắt buộc)',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                a.requiresApproval
                    ? 'Tiện ích cần ban quản lý duyệt. Hủy trước giờ bắt đầu ${a.cancelDeadlineHours} tiếng.'
                    : 'Hủy trước giờ bắt đầu ${a.cancelDeadlineHours} tiếng.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Đặt'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final b = await ref
          .read(amenitiesRepositoryProvider)
          .book(
            amenityId: a.id,
            apartmentId: apartmentId,
            date: _date,
            startTime: slot.startLabel,
            people: people,
            note: note.text,
          );
      if (!mounted) return;
      showSnack(
        context,
        b.status == BookingStatus.pending
            ? 'Đã gửi yêu cầu, chờ duyệt'
            : 'Đặt thành công',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // SLOT_FULL: người khác vừa đặt hết chỗ -> tải lại lưới ngay
      showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      ref.invalidate(amenitySlotsProvider(_slotKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final async = ref.watch(amenityDetailProvider(widget.amenityId));
    final a = async.value;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(a?.name ?? 'Tiện ích'),
        actions: [
          if (a != null && (user?.isManager ?? false)) ...[
            IconButton(
              tooltip: 'Sửa',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push('/amenities/${a.id}/edit');
                ref.invalidate(amenityDetailProvider(a.id));
                ref.invalidate(amenitySlotsProvider);
              },
            ),
            IconButton(
              tooltip: a.isActive ? 'Tạm ngưng' : 'Mở lại',
              icon: Icon(
                a.isActive
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
              onPressed: () => _toggleActive(a),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(amenityDetailProvider(widget.amenityId)),
        ),
        data: (a) => RefreshIndicator(
          onRefresh: () => ref.refresh(amenitySlotsProvider(_slotKey).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!a.isActive)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: StatusChip(
                    label: 'Tạm ngưng',
                    tone: StatusTone.danger,
                  ),
                ),
              if ((a.location ?? '').isNotEmpty)
                InfoRow(
                  label: 'Vị trí',
                  value: a.location!,
                  icon: Icons.place_outlined,
                ),
              InfoRow(
                label: 'Giờ mở cửa',
                value: '${a.openTime}–${a.closeTime}',
                icon: Icons.schedule,
              ),
              InfoRow(
                label: 'Mỗi lượt',
                value: '${a.slotDuration} phút · tối đa ${a.capacity} người',
                icon: Icons.groups_outlined,
              ),
              InfoRow(
                label: 'Đặt / hủy',
                value: [
                  a.requiresApproval ? 'Cần duyệt' : 'Xác nhận ngay',
                  'hủy trước ${a.cancelDeadlineHours} tiếng',
                ].join(' · '),
                icon: Icons.rule,
              ),
              if ((a.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(a.description!),
              ],
              if ((a.rules ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Nội quy', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(a.rules!),
              ],
              const Divider(height: 32),
              Row(
                children: [
                  Text(
                    'Chọn ngày',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(formatDate(_date)),
                  ),
                ],
              ),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 14,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final d = DateTime(today.year, today.month, today.day + i);
                    final selected = d == _date;
                    return ChoiceChip(
                      selected: selected,
                      onSelected: (_) => setState(() => _date = d),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(i == 0 ? 'Hôm nay' : _days[d.weekday % 7]),
                          Text('${d.day}/${d.month}'),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SlotGrid(
                slotKey: _slotKey,
                onTap: user?.isResident ?? false
                    ? (slot) => _book(a, slot)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotGrid extends ConsumerWidget {
  const _SlotGrid({required this.slotKey, this.onTap});

  final (String, String) slotKey;
  final void Function(SlotInfo slot)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(amenitySlotsProvider(slotKey));
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(amenitySlotsProvider(slotKey)),
      ),
      data: (slots) => slots.isEmpty
          ? const Text('Không có khung giờ')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in slots)
                  SizedBox(
                    width: 104,
                    child: Material(
                      color: s.available
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: s.available && onTap != null
                            ? () => onTap!(s)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          child: Column(
                            children: [
                              Text(
                                s.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                s.available
                                    ? 'Còn ${s.remaining}'
                                    : s.remaining == 0
                                    ? 'Hết chỗ'
                                    : 'Không đặt được',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ======================================================================== UC-35 form (Manager)
class AmenityFormPage extends ConsumerStatefulWidget {
  const AmenityFormPage({super.key, this.amenityId});
  final String? amenityId;

  @override
  ConsumerState<AmenityFormPage> createState() => _AmenityFormPageState();
}

class _AmenityFormPageState extends ConsumerState<AmenityFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();
  final _capacity = TextEditingController(text: '10');
  final _cancelHours = TextEditingController(text: '2');
  TimeOfDay _open = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _close = const TimeOfDay(hour: 21, minute: 0);
  int _slotDuration = 60;
  bool _requiresApproval = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.amenityId != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _location,
      _description,
      _rules,
      _capacity,
      _cancelHours,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _fill(Amenity a) {
    if (_loaded) return;
    _loaded = true;
    _name.text = a.name;
    _location.text = a.location ?? '';
    _description.text = a.description ?? '';
    _rules.text = a.rules ?? '';
    _capacity.text = '${a.capacity}';
    _cancelHours.text = '${a.cancelDeadlineHours}';
    _open = _parse(a.openTime);
    _close = _parse(a.closeTime);
    _slotDuration = a.slotDuration;
    _requiresApproval = a.requiresApproval;
  }

  Future<void> _pickTime(bool open) async {
    final t = await showTimePicker(
      context: context,
      initialTime: open ? _open : _close,
    );
    if (t != null) setState(() => open ? _open = t : _close = t);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final open = _open.hour * 60 + _open.minute;
    final close = _close.hour * 60 + _close.minute;
    if (close - open < _slotDuration) {
      return showSnack(
        context,
        'Giờ đóng phải sau giờ mở ít nhất một lượt',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      await ref.read(amenitiesRepositoryProvider).save(widget.amenityId, {
        'name': _name.text.trim(),
        'location': _location.text.trim(),
        'description': _description.text.trim(),
        'rules': _rules.text.trim(),
        'openTime': _fmt(_open),
        'closeTime': _fmt(_close),
        'slotDuration': _slotDuration,
        'capacity': int.parse(_capacity.text),
        'requiresApproval': _requiresApproval,
        'cancelDeadlineHours': int.parse(_cancelHours.text),
      });
      if (!mounted) return;
      showSnack(
        context,
        _isEdit ? 'Đã lưu (áp dụng cho lượt đặt mới)' : 'Đã thêm tiện ích',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form() => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Tên tiện ích'),
          validator: (v) =>
              (v ?? '').trim().length < 2 ? 'Nhập tên tiện ích' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _location,
          decoration: const InputDecoration(labelText: 'Vị trí'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mở cửa'),
                subtitle: Text(_fmt(_open)),
                onTap: () => _pickTime(true),
              ),
            ),
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đóng cửa'),
                subtitle: Text(_fmt(_close)),
                onTap: () => _pickTime(false),
              ),
            ),
          ],
        ),
        DropdownButtonFormField<int>(
          initialValue: _slotDuration,
          decoration: const InputDecoration(labelText: 'Thời lượng mỗi lượt'),
          items: [
            for (final m in {30, 60, 90, 120, 180, _slotDuration})
              DropdownMenuItem(value: m, child: Text('$m phút')),
          ],
          onChanged: (v) => setState(() => _slotDuration = v ?? 60),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _capacity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Sức chứa mỗi lượt (người)',
          ),
          validator: (v) =>
              (int.tryParse(v ?? '') ?? 0) < 1 ? 'Tối thiểu 1' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _cancelHours,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Hủy trước giờ bắt đầu (tiếng)',
          ),
          validator: (v) =>
              (int.tryParse(v ?? '') ?? -1) < 0 ? 'Từ 0 trở lên' : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cần nhân viên tiện ích duyệt'),
          value: _requiresApproval,
          onChanged: (v) => setState(() => _requiresApproval = v),
        ),
        TextFormField(
          controller: _description,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Mô tả'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _rules,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Nội quy'),
        ),
        const SizedBox(height: 24),
        LoadingButton(loading: _saving, onPressed: _submit, label: 'Lưu'),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa tiện ích' : 'Thêm tiện ích')),
      body: !_isEdit
          ? _form()
          : ref
                .watch(amenityDetailProvider(widget.amenityId!))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ErrorView(error: e),
                  data: (a) {
                    _fill(a);
                    return _form();
                  },
                ),
    );
  }
}
