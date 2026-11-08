import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/multipart.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/media_widgets.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../apartments/application/apartments_providers.dart';
import '../../apartments/data/models.dart';
import '../data/models.dart';
import '../data/vehicles_repository.dart';

/// Một dòng xe trong danh sách.
class VehicleTile extends StatelessWidget {
  const VehicleTile({
    super.key,
    required this.vehicle,
    this.onTap,
    this.showOwner = false,
  });

  final Vehicle vehicle;
  final VoidCallback? onTap;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final meta = [
      v.type.label,
      if ((v.brand ?? '').isNotEmpty) v.brand!,
      if (v.apartmentCode != null) 'Căn ${v.apartmentCode}',
      if (showOwner && v.ownerName != null) v.ownerName!,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(
          v.type == VehicleType.car
              ? Icons.directions_car_outlined
              : Icons.two_wheeler_outlined,
        ),
      ),
      title: Text(
        v.displayPlate,
        style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
      ),
      subtitle: Text(meta),
      trailing: StatusChip(label: v.status.label, tone: v.status.tone),
    );
  }
}

// ======================================================================== UC-15 Resident
/// Xe của tôi: xe của các căn hộ đang cư trú.
class MyVehiclesPage extends ConsumerStatefulWidget {
  const MyVehiclesPage({super.key});

  @override
  ConsumerState<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends ConsumerState<MyVehiclesPage> {
  int _reload = 0;

  Future<void> _open(String route) async {
    await context.push(route);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(vehiclesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Xe của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/vehicles/new'),
        icon: const Icon(Icons.add),
        label: const Text('Đăng ký xe'),
      ),
      body: PagedListView<Vehicle>(
        key: ValueKey(_reload),
        fetch: (page) => repo.listMine(page: page),
        emptyText: 'Chưa đăng ký xe nào',
        itemBuilder: (context, v) =>
            VehicleTile(vehicle: v, onTap: () => _open('/vehicles/${v.id}')),
      ),
    );
  }
}

// ======================================================================== UC-13 đăng ký
class VehicleFormPage extends ConsumerStatefulWidget {
  const VehicleFormPage({super.key});

  @override
  ConsumerState<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends ConsumerState<VehicleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _brand = TextEditingController();
  final _color = TextEditingController();
  VehicleType _type = VehicleType.motorbike;
  String? _apartmentId;
  UploadFile? _image;
  bool _saving = false;

  @override
  void dispose() {
    _plate.dispose();
    _brand.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Apartment> apartments) async {
    final apartmentId =
        _apartmentId ?? (apartments.length == 1 ? apartments.first.id : null);
    if (!_formKey.currentState!.validate() || apartmentId == null) return;
    setState(() => _saving = true);
    try {
      final v = await ref
          .read(vehiclesRepositoryProvider)
          .register(
            apartmentId: apartmentId,
            type: _type,
            plateNumber: _plate.text,
            brand: _brand.text,
            color: _color.text,
            image: _image,
          );
      if (!mounted) return;
      showSnack(
        context,
        'Đã gửi đăng ký xe ${v.displayPlate}, chờ Bảo vệ duyệt',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apartments = ref.watch(myApartmentsProvider);
    return UnsavedChangesGuard(
      isDirty: () =>
          _plate.text.trim().isNotEmpty ||
          _brand.text.trim().isNotEmpty ||
          _color.text.trim().isNotEmpty ||
          _image != null,
      child: Scaffold(
        appBar: AppBar(title: const Text('Đăng ký xe')),
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
                      SegmentedButton<VehicleType>(
                        segments: [
                          for (final t in VehicleType.values)
                            ButtonSegment(
                              value: t,
                              label: Text(t.label),
                              icon: Icon(
                                t == VehicleType.car
                                    ? Icons.directions_car_outlined
                                    : Icons.two_wheeler_outlined,
                              ),
                            ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (s) =>
                            setState(() => _type = s.first),
                      ),
                      const SizedBox(height: 16),
                      if (list.length > 1) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _apartmentId,
                          decoration: const InputDecoration(
                            labelText: 'Căn hộ',
                          ),
                          items: [
                            for (final a in list)
                              DropdownMenuItem(
                                value: a.id,
                                child: Text(a.code),
                              ),
                          ],
                          validator: (v) => v == null ? 'Chọn căn hộ' : null,
                          onChanged: (v) => setState(() => _apartmentId = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _plate,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Biển số',
                          hintText: 'VD: 30A-123.45',
                        ),
                        validator: (v) =>
                            plateRegex.hasMatch(normalizePlate(v ?? ''))
                            ? null
                            : 'Biển số không đúng định dạng',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _brand,
                        decoration: const InputDecoration(
                          labelText: 'Hãng xe (không bắt buộc)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _color,
                        decoration: const InputDecoration(
                          labelText: 'Màu xe (không bắt buộc)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ảnh xe / cà vẹt',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ImagePickerField(
                        max: 1,
                        onChanged: (f) => _image = f.firstOrNull,
                      ),
                      const SizedBox(height: 24),
                      LoadingButton(
                        loading: _saving,
                        onPressed: () => _submit(list),
                        label: 'Gửi đăng ký',
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ======================================================================== UC-14, 15 Bảo vệ / Manager
/// Quản lý xe: hàng chờ duyệt, tra cứu biển số.
class VehiclesManagePage extends ConsumerStatefulWidget {
  const VehiclesManagePage({super.key});

  @override
  ConsumerState<VehiclesManagePage> createState() => _VehiclesManagePageState();
}

class _VehiclesManagePageState extends ConsumerState<VehiclesManagePage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _plate = '';
  VehicleStatus? _status = VehicleStatus.pending;
  int _reload = 0;

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
      () => setState(() {
        _plate = q.trim();
        // Tra biển số ở cổng: tìm trên mọi trạng thái, không chỉ tab đang chọn
        if (_plate.isNotEmpty) _status = null;
      }),
    );
  }

  Future<void> _open(Vehicle v) async {
    await context.push('/vehicles/${v.id}');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(vehiclesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý xe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Tra cứu biển số',
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
                for (final s in <VehicleStatus?>[null, ...VehicleStatus.values])
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
            child: PagedListView<Vehicle>(
              key: ValueKey('${_status?.name}|$_plate|$_reload'),
              fetch: (page) =>
                  repo.list(status: _status, plate: _plate, page: page),
              emptyText: 'Không có xe phù hợp',
              itemBuilder: (context, v) => VehicleTile(
                vehicle: v,
                showOwner: true,
                onTap: () => _open(v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================== Chi tiết (mọi vai trò)
class VehicleDetailPage extends ConsumerStatefulWidget {
  const VehicleDetailPage({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<VehicleDetailPage> createState() => _VehicleDetailPageState();
}

class _VehicleDetailPageState extends ConsumerState<VehicleDetailPage> {
  bool _busy = false;

  void _reload() => ref.invalidate(vehicleDetailProvider(widget.vehicleId));

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
              ? 'Hồ sơ đã thay đổi, đã tải lại'
              : e.message,
          error: true,
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      _reload();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Vehicle v) async {
    final ok = await confirmDialog(
      context,
      title: 'Duyệt xe',
      message: 'Duyệt xe ${v.displayPlate}?',
      confirmText: 'Duyệt',
    );
    if (ok) {
      await _run(
        () => ref.read(vehiclesRepositoryProvider).approve(v.id),
        'Đã duyệt xe',
      );
    }
  }

  Future<void> _reject(Vehicle v) async {
    final reason = await reasonDialog(
      context,
      title: 'Từ chối đăng ký xe',
      confirmText: 'Từ chối',
      destructive: true,
    );
    if (reason != null) {
      await _run(
        () => ref.read(vehiclesRepositoryProvider).reject(v.id, reason),
        'Đã từ chối',
      );
    }
  }

  Future<void> _deactivate(Vehicle v) async {
    final ok = await confirmDialog(
      context,
      title: v.status == VehicleStatus.pending
          ? 'Hủy đăng ký'
          : 'Ngừng sử dụng xe',
      message: v.status == VehicleStatus.pending
          ? 'Hủy hồ sơ đăng ký xe ${v.displayPlate}?'
          : 'Xe ${v.displayPlate} sẽ ngừng gửi tại tòa nhà từ kỳ phí sau.',
      destructive: true,
    );
    if (ok) {
      await _run(
        () => ref.read(vehiclesRepositoryProvider).deactivate(v.id),
        'Đã cập nhật',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vehicleDetailProvider(widget.vehicleId));
    final v = async.value;
    return Scaffold(
      appBar: AppBar(title: Text(v?.displayPlate ?? 'Chi tiết xe')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: _reload),
        data: (v) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.displayPlate,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 2),
                  ),
                ),
                StatusChip(label: v.status.label, tone: v.status.tone),
              ],
            ),
            const SizedBox(height: 12),
            if (v.imageUrl != null) ...[
              NetworkImageStrip([v.imageUrl!], size: 140),
              const SizedBox(height: 12),
            ],
            InfoRow(
              label: 'Loại xe',
              value: v.type.label,
              icon: Icons.category_outlined,
            ),
            if ((v.brand ?? '').isNotEmpty)
              InfoRow(
                label: 'Hãng',
                value: v.brand!,
                icon: Icons.local_offer_outlined,
              ),
            if ((v.color ?? '').isNotEmpty)
              InfoRow(
                label: 'Màu',
                value: v.color!,
                icon: Icons.palette_outlined,
              ),
            if (v.apartmentCode != null)
              InfoRow(
                label: 'Căn hộ',
                value: v.apartmentCode!,
                icon: Icons.home_outlined,
              ),
            if (v.ownerName != null)
              InfoRow(
                label: 'Người đăng ký',
                value: [
                  v.ownerName!,
                  if (v.ownerPhone != null) v.ownerPhone!,
                ].join(' · '),
                icon: Icons.person_outline,
              ),
            InfoRow(
              label: 'Ngày đăng ký',
              value: formatDateTime(v.createdAt),
              icon: Icons.event_outlined,
            ),
            if (v.reviewedAt != null)
              InfoRow(
                label: 'Xét duyệt',
                value: [
                  formatDateTime(v.reviewedAt),
                  if (v.reviewedByName != null) v.reviewedByName!,
                ].join(' · '),
                icon: Icons.verified_user_outlined,
              ),
            if (v.rejectReason != null)
              InfoRow(
                label: 'Lý do từ chối',
                value: v.rejectReason!,
                icon: Icons.info_outline,
              ),
            if (v.deactivatedAt != null)
              InfoRow(
                label: 'Ngừng từ',
                value: formatDateTime(v.deactivatedAt),
                icon: Icons.block_outlined,
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
                          if (v.allowedActions.contains('deactivate'))
                            OutlinedButton(
                              onPressed: () => _deactivate(v),
                              child: Text(
                                v.status == VehicleStatus.pending
                                    ? 'Hủy đăng ký'
                                    : 'Ngừng sử dụng',
                              ),
                            ),
                          if (v.allowedActions.contains('reject'))
                            OutlinedButton(
                              onPressed: () => _reject(v),
                              child: const Text('Từ chối'),
                            ),
                          if (v.allowedActions.contains('approve'))
                            FilledButton(
                              onPressed: () => _approve(v),
                              child: const Text('Duyệt'),
                            ),
                        ],
                      ),
              ),
            ),
    );
  }
}
