import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../../users/data/users_repository.dart';
import '../application/apartments_providers.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';
import 'widgets.dart';

enum ResidentFormMode {
  /// UC-08: Quản lý thêm hồ sơ (hiệu lực ngay)
  create,

  /// UC-08: Quản lý sửa hồ sơ
  edit,

  /// UC-09: Chủ hộ khai báo thành viên / người thuê (chờ duyệt)
  register,
}

class ResidentFormPage extends ConsumerWidget {
  const ResidentFormPage({super.key, required this.mode, this.apartmentId, this.residentId});

  final ResidentFormMode mode;
  final String? apartmentId;
  final String? residentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode != ResidentFormMode.edit) {
      return _ResidentForm(mode: mode, apartmentId: apartmentId!);
    }
    final rec = ref.watch(residentDetailProvider(residentId!));
    return rec.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(residentDetailProvider(residentId!)),
        ),
      ),
      data: (r) => _ResidentForm(mode: mode, apartmentId: r.apartmentId, initial: r),
    );
  }
}

class _ResidentForm extends ConsumerStatefulWidget {
  const _ResidentForm({required this.mode, required this.apartmentId, this.initial});

  final ResidentFormMode mode;
  final String apartmentId;
  final ResidentRecord? initial;

  @override
  ConsumerState<_ResidentForm> createState() => _ResidentFormState();
}

class _ResidentFormState extends ConsumerState<_ResidentForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _idNumber = TextEditingController(text: widget.initial?.idNumber);
  late final _note = TextEditingController(text: widget.initial?.note);
  late ResidentRelation _relation =
      widget.initial?.relation ??
      (widget.mode == ResidentFormMode.register ? ResidentRelation.member : ResidentRelation.owner);
  late DateTime? _dob = widget.initial?.dateOfBirth;
  DateTime? _moveIn;
  bool _isPayer = false;
  late String? _linkedUserId = widget.initial?.userId;
  late String? _linkedUserLabel = widget.initial?.userEmail;
  bool _saving = false;

  bool get _isRegister => widget.mode == ResidentFormMode.register;

  @override
  void dispose() {
    for (final c in [_name, _phone, _idNumber, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAccount() async {
    final user = await showDialog<AppUser>(
      context: context,
      builder: (_) => const _AccountPicker(),
    );
    if (user != null) {
      setState(() {
        _linkedUserId = user.id;
        _linkedUserLabel = user.email;
        if (_name.text.trim().isEmpty) _name.text = user.fullName;
        if (_phone.text.trim().isEmpty && user.phone != null) _phone.text = user.phone!;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = ResidentInput(
      fullName: _name.text,
      relation: _relation,
      phone: _phone.text,
      idNumber: _idNumber.text,
      dateOfBirth: _dob,
      note: _note.text,
      userId: _linkedUserId,
      moveInDate: _moveIn,
      isPayer: _isPayer,
    );
    final repo = ref.read(apartmentsRepositoryProvider);
    try {
      switch (widget.mode) {
        case ResidentFormMode.create:
          await repo.createResident(widget.apartmentId, input);
        case ResidentFormMode.edit:
          await repo.updateResident(widget.initial!.id, input);
        case ResidentFormMode.register:
          await repo.registerMember(widget.apartmentId, input);
      }
      invalidateApartmentData(ref);
      if (!mounted) return;
      showSnack(context, switch (widget.mode) {
        ResidentFormMode.create => 'Đã thêm cư dân',
        ResidentFormMode.edit => 'Đã cập nhật hồ sơ',
        ResidentFormMode.register => 'Đã gửi đăng ký, vui lòng chờ Ban quản lý duyệt',
      });
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relations = _isRegister
        ? const [ResidentRelation.member, ResidentRelation.tenant]
        : ResidentRelation.values;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.mode) {
          ResidentFormMode.create => 'Thêm cư dân',
          ResidentFormMode.edit => 'Sửa hồ sơ cư trú',
          ResidentFormMode.register => 'Khai báo thành viên',
        }),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isRegister)
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Thông tin sẽ được gửi tới Ban quản lý để duyệt trước khi ghi nhận cư trú.',
                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<ResidentRelation>(
              segments: [for (final r in relations) ButtonSegment(value: r, label: Text(r.label))],
              selected: {_relation},
              onSelectionChanged: (s) => setState(() => _relation = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, 'Họ tên'),
              decoration: const InputDecoration(labelText: 'Họ tên'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: Validators.optionalPhone,
              decoration: const InputDecoration(labelText: 'Số điện thoại (không bắt buộc)'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _idNumber,
              keyboardType: TextInputType.number,
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return null;
                return RegExp(r'^(\d{9}|\d{12})$').hasMatch(s)
                    ? null
                    : 'CCCD/CMND gồm 9 hoặc 12 chữ số';
              },
              decoration: const InputDecoration(labelText: 'CCCD / CMND (không bắt buộc)'),
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Ngày sinh',
              value: _dob,
              lastDate: DateTime.now(),
              onChanged: (d) => setState(() => _dob = d),
            ),
            if (widget.mode != ResidentFormMode.edit) ...[
              const SizedBox(height: 16),
              DateField(
                label: 'Ngày chuyển đến (mặc định hôm nay)',
                value: _moveIn,
                onChanged: (d) => setState(() => _moveIn = d),
              ),
            ],
            if (!_isRegister) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(_linkedUserLabel ?? 'Chưa liên kết tài khoản'),
                  subtitle: const Text('Tài khoản ứng dụng của người này (nếu có)'),
                  trailing: _linkedUserId == null
                      ? TextButton(onPressed: _pickAccount, child: const Text('Liên kết'))
                      : IconButton(
                          tooltip: 'Gỡ liên kết',
                          icon: const Icon(Icons.link_off),
                          onPressed: () => setState(() {
                            _linkedUserId = null;
                            _linkedUserLabel = null;
                          }),
                        ),
                ),
              ),
            ],
            if (widget.mode == ResidentFormMode.create)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPayer,
                onChanged: (v) => setState(() => _isPayer = v),
                title: const Text('Người nộp phí của căn hộ'),
                subtitle: const Text('Mặc định là chủ hộ nếu không chọn'),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              loading: _saving,
              onPressed: _submit,
              label: switch (widget.mode) {
                ResidentFormMode.create => 'Thêm cư dân',
                ResidentFormMode.edit => 'Lưu thay đổi',
                ResidentFormMode.register => 'Gửi đăng ký',
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tìm tài khoản có vai trò Cư dân để liên kết với hồ sơ cư trú.
class _AccountPicker extends ConsumerStatefulWidget {
  const _AccountPicker();

  @override
  ConsumerState<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends ConsumerState<_AccountPicker> {
  Timer? _debounce;
  String _q = '';
  late Future<List<AppUser>> _future = _search();

  Future<List<AppUser>> _search() async {
    final res = await ref
        .read(usersRepositoryProvider)
        .list(
          filter: UserFilter(q: _q, role: UserRole.resident, status: UserStatus.active),
        );
    return res.items;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Liên kết tài khoản'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên, email, SĐT',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  setState(() {
                    _q = q;
                    _future = _search();
                  });
                });
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<AppUser>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) return ErrorView(error: snap.error!);
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final users = snap.data!;
                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        'Không tìm thấy. Tạo tài khoản Cư dân ở mục "Tài khoản" trước.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final u in users)
                        ListTile(
                          leading: CircleAvatar(child: Text(u.initials)),
                          title: Text(u.fullName),
                          subtitle: Text(u.email),
                          onTap: () => Navigator.pop(context, u),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))],
    );
  }
}
