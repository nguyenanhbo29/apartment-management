import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../apartments/data/apartments_repository.dart';
import '../../apartments/data/models.dart';
import '../../apartments/presentation/widgets.dart';
import '../../auth/data/app_user.dart';
import '../data/communication_repository.dart';
import '../data/models.dart';

/// UC-43: Quản lý đăng bảng tin theo đối tượng. Đăng rồi không sửa, chỉ ghim / gỡ.
class AnnouncementFormPage extends ConsumerStatefulWidget {
  const AnnouncementFormPage({super.key});

  @override
  ConsumerState<AnnouncementFormPage> createState() => _AnnouncementFormPageState();
}

class _AnnouncementFormPageState extends ConsumerState<AnnouncementFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _floors = TextEditingController();
  AudienceType _type = AudienceType.all;
  final _roles = <UserRole>{};
  final _apartments = <String, String>{}; // id -> code
  bool _pinned = false;
  DateTime? _expiresAt;
  bool _saving = false;
  String? _audienceError;

  @override
  void dispose() {
    for (final c in [_title, _content, _floors]) {
      c.dispose();
    }
    super.dispose();
  }

  List<int>? _parseFloors() {
    final parts = _floors.text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty);
    final floors = parts.map(int.tryParse).toList();
    if (floors.isEmpty || floors.contains(null)) return null;
    return floors.cast<int>().toSet().toList()..sort();
  }

  Audience? _buildAudience() {
    switch (_type) {
      case AudienceType.all:
        return const Audience(type: AudienceType.all);
      case AudienceType.roles:
        if (_roles.isEmpty) return null;
        return Audience(type: AudienceType.roles, roles: _roles.toList());
      case AudienceType.floors:
        final floors = _parseFloors();
        return floors == null ? null : Audience(type: AudienceType.floors, floors: floors);
      case AudienceType.apartments:
        if (_apartments.isEmpty) return null;
        return Audience(type: AudienceType.apartments, apartmentIds: _apartments.keys.toList());
    }
  }

  Future<void> _pickApartments() async {
    final picked = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ApartmentPicker(initial: Map.of(_apartments)),
    );
    if (picked != null) {
      setState(() {
        _apartments
          ..clear()
          ..addAll(picked);
        _audienceError = null;
      });
    }
  }

  Future<void> _submit() async {
    final audience = _buildAudience();
    setState(() {
      _audienceError = audience == null
          ? switch (_type) {
              AudienceType.roles => 'Chọn ít nhất một vai trò',
              AudienceType.floors => 'Nhập số tầng, cách nhau bởi dấu phẩy (VD: 1, 2, 5)',
              AudienceType.apartments => 'Chọn ít nhất một căn hộ',
              AudienceType.all => null,
            }
          : null;
    });
    if (!_formKey.currentState!.validate() || audience == null) return;

    final ok = await confirmDialog(
      context,
      title: 'Đăng bảng tin',
      message:
          'Gửi tới: ${audience.label}.\n'
          'Mỗi người nhận sẽ có một thông báo. Tin đã đăng không sửa được, chỉ gỡ.',
      confirmText: 'Đăng',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final ann = await ref
          .read(communicationRepositoryProvider)
          .createAnnouncement(
            title: _title.text,
            content: _content.text,
            audience: audience,
            isPinned: _pinned,
            expiresAt: _expiresAt,
          );
      if (!mounted) return;
      showSnack(context, 'Đã đăng, gửi tới ${ann.recipientCount} người');
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
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(title: const Text('Đăng bảng tin')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 200,
              validator: (v) => Validators.required(v, 'Tiêu đề'),
              decoration: const InputDecoration(labelText: 'Tiêu đề'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _content,
              minLines: 5,
              maxLines: 12,
              validator: (v) => Validators.required(v, 'Nội dung'),
              decoration: const InputDecoration(labelText: 'Nội dung', alignLabelWithHint: true),
            ),
            const SizedBox(height: 20),
            Text('Gửi tới', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in AudienceType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _audienceError = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ..._audienceInput(theme),
            if (_audienceError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _audienceError!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('Ghim lên đầu bảng tin'),
            ),
            DateField(
              label: 'Ngày hết hạn hiển thị (không bắt buộc)',
              value: _expiresAt,
              firstDate: tomorrow,
              onChanged: (d) => setState(() => _expiresAt = d),
            ),
            const SizedBox(height: 24),
            LoadingButton(loading: _saving, onPressed: _submit, label: 'Đăng tin'),
          ],
        ),
      ),
    );
  }

  List<Widget> _audienceInput(ThemeData theme) {
    switch (_type) {
      case AudienceType.all:
        return [
          Text(
            'Mọi tài khoản đang hoạt động (cư dân, nhân viên, kế toán, quản lý).',
            style: theme.textTheme.bodySmall,
          ),
        ];
      case AudienceType.roles:
        return [
          Wrap(
            spacing: 8,
            children: [
              for (final r in UserRole.values)
                FilterChip(
                  label: Text(r.label),
                  selected: _roles.contains(r),
                  onSelected: (sel) => setState(() {
                    sel ? _roles.add(r) : _roles.remove(r);
                    _audienceError = null;
                  }),
                ),
            ],
          ),
        ];
      case AudienceType.floors:
        return [
          TextField(
            controller: _floors,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() => _audienceError = null),
            decoration: const InputDecoration(
              labelText: 'Các tầng',
              hintText: 'VD: 1, 2, 5',
              helperText: 'Gửi tới cư dân đang ở các tầng này',
            ),
          ),
        ];
      case AudienceType.apartments:
        return [
          if (_apartments.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _apartments.entries)
                  InputChip(
                    label: Text(e.value),
                    onDeleted: () => setState(() => _apartments.remove(e.key)),
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickApartments,
              icon: const Icon(Icons.apartment_outlined),
              label: Text(_apartments.isEmpty ? 'Chọn căn hộ' : 'Thay đổi'),
            ),
          ),
        ];
    }
  }
}

/// Chọn nhiều căn hộ (tìm theo mã).
class _ApartmentPicker extends ConsumerStatefulWidget {
  const _ApartmentPicker({required this.initial});
  final Map<String, String> initial;

  @override
  ConsumerState<_ApartmentPicker> createState() => _ApartmentPickerState();
}

class _ApartmentPickerState extends ConsumerState<_ApartmentPicker> {
  late final Map<String, String> _selected = widget.initial;
  Timer? _debounce;
  late Future<List<Apartment>> _future = _search('');

  Future<List<Apartment>> _search(String q) async =>
      (await ref.read(apartmentsRepositoryProvider).listApartments(q: q)).items;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Chọn căn hộ (${_selected.length})'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo mã căn hộ',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 400),
                  () => setState(() { _future = _search(q); }),
                );
              },
            ),
            Expanded(
              child: FutureBuilder<List<Apartment>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) return ErrorView(error: snap.error!);
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView(
                    children: [
                      for (final a in snap.data!)
                        CheckboxListTile(
                          value: _selected.containsKey(a.id),
                          title: Text('Căn ${a.code}'),
                          subtitle: Text('Tầng ${a.floor} · ${a.status.label}'),
                          onChanged: (v) => setState(() {
                            v == true ? _selected[a.id] = a.code : _selected.remove(a.id);
                          }),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Xong')),
      ],
    );
  }
}
