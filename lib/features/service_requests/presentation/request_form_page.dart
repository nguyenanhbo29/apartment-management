import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/multipart.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../apartments/application/apartments_providers.dart';
import '../../apartments/data/models.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';
import 'widgets.dart';

/// UC-27, UC-28: Tạo phiếu sửa chữa / phản ánh (một form, tham số theo loại).
class RequestFormPage extends ConsumerStatefulWidget {
  const RequestFormPage({super.key});

  @override
  ConsumerState<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends ConsumerState<RequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  RequestType _type = RequestType.repair;
  RequestCategory? _category;
  RequestPriority _priority = RequestPriority.normal;
  String? _apartmentId;
  List<UploadFile> _images = const [];
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Apartment> apartments) async {
    final apartmentId =
        _apartmentId ?? (apartments.length == 1 ? apartments.first.id : null);
    if (!_formKey.currentState!.validate() || apartmentId == null) return;
    setState(() => _saving = true);
    try {
      final created = await ref
          .read(serviceRequestsRepositoryProvider)
          .create(
            apartmentId: apartmentId,
            type: _type,
            category: _category!,
            priority: _priority,
            title: _title.text.trim(),
            description: _description.text.trim(),
            images: _images,
          );
      if (!mounted) return;
      showSnack(context, 'Đã gửi phiếu ${created.code}');
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
          _title.text.trim().isNotEmpty ||
          _description.text.trim().isNotEmpty ||
          _category != null ||
          _images.isNotEmpty,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tạo phiếu')),
        body: apartments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(myApartmentsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Bạn chưa được ghi nhận cư trú tại căn hộ nào nên chưa thể gửi phiếu.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<RequestType>(
                    segments: [
                      for (final t in RequestType.values)
                        ButtonSegment(
                          value: t,
                          label: Text(t.label),
                          icon: Icon(
                            t == RequestType.repair
                                ? Icons.build_outlined
                                : Icons.report_outlined,
                          ),
                        ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      // Danh mục đang chọn không thuộc loại mới thì bỏ chọn
                      if (_category != null &&
                          !_type.categories.contains(_category)) {
                        _category = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
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
                  DropdownButtonFormField<RequestCategory>(
                    // Đổi loại phiếu -> dựng lại để nhận danh sách và giá trị mới
                    key: ValueKey(_type),
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Danh mục'),
                    items: [
                      for (final c in _type.categories)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    validator: (v) => v == null ? 'Chọn danh mục' : null,
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Tiêu đề'),
                    maxLength: 150,
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Tiêu đề tối thiểu 3 ký tự'
                        : null,
                  ),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả chi tiết',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    maxLength: 2000,
                    validator: (v) => (v ?? '').trim().length < 5
                        ? 'Mô tả tối thiểu 5 ký tự'
                        : null,
                  ),
                  DropdownButtonFormField<RequestPriority>(
                    initialValue: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Mức độ ưu tiên',
                    ),
                    items: [
                      for (final p in RequestPriority.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _priority = v ?? RequestPriority.normal),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ảnh đính kèm (tối đa 5)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ImagePickerField(onChanged: (files) => _images = files),
                  const SizedBox(height: 24),
                  LoadingButton(
                    loading: _saving,
                    onPressed: () => _submit(list),
                    label: 'Gửi phiếu',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
