import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../application/apartments_providers.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';

/// UC-06: Thêm / sửa căn hộ (Quản lý).
class ApartmentFormPage extends ConsumerWidget {
  const ApartmentFormPage({super.key, this.apartmentId});

  final String? apartmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = apartmentId;
    if (id == null) return const _Form(initial: null);
    final apt = ref.watch(apartmentDetailProvider(id));
    return apt.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: e, onRetry: () => ref.invalidate(apartmentDetailProvider(id))),
      ),
      data: (a) => _Form(initial: a),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial});
  final Apartment? initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.initial?.code);
  late final _floor = TextEditingController(text: widget.initial?.floor.toString());
  late final _area = TextEditingController(text: widget.initial?.area.toString());
  late final _bedrooms = TextEditingController(text: widget.initial?.bedrooms?.toString());
  late final _note = TextEditingController(text: widget.initial?.note);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_code, _floor, _area, _bedrooms, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(apartmentsRepositoryProvider)
          .saveApartment(
            id: widget.initial?.id,
            code: _code.text,
            floor: int.parse(_floor.text.trim()),
            area: double.parse(_area.text.trim().replaceAll(',', '.')),
            bedrooms: int.tryParse(_bedrooms.text.trim()),
            note: _note.text,
          );
      invalidateApartmentData(ref);
      if (!mounted) return;
      showSnack(context, widget.initial == null ? 'Đã thêm căn hộ' : 'Đã cập nhật căn hộ');
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Sửa căn hộ ${widget.initial!.code}' : 'Thêm căn hộ')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                final err = Validators.required(v, 'Mã căn hộ');
                if (err != null) return err;
                return RegExp(r'^[A-Za-z0-9.\-_]+$').hasMatch(v!.trim())
                    ? null
                    : 'Mã chỉ gồm chữ, số và . - _';
              },
              decoration: const InputDecoration(labelText: 'Mã căn hộ', hintText: 'VD: A-1205'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _floor,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                    validator: (v) => int.tryParse(v?.trim() ?? '') == null ? 'Nhập số tầng' : null,
                    decoration: const InputDecoration(labelText: 'Tầng'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _bedrooms,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Số phòng ngủ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _area,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                return (n == null || n <= 0) ? 'Diện tích phải lớn hơn 0' : null;
              },
              decoration: const InputDecoration(
                labelText: 'Diện tích',
                suffixText: 'm²',
                helperText: 'Dùng để tính phí quản lý',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              loading: _saving,
              onPressed: _submit,
              label: isEdit ? 'Lưu thay đổi' : 'Thêm căn hộ',
            ),
          ],
        ),
      ),
    );
  }
}
