import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/multipart.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/media.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/models.dart';

class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: status.label, tone: status.tone);
}

const overdueChip = StatusChip(
  label: 'Quá hạn',
  tone: StatusTone.danger,
  icon: Icons.schedule,
);

/// Một dòng phiếu trong danh sách.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.onTap,
    this.showAssignee = false,
  });

  final ServiceRequest request;
  final VoidCallback? onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final theme = Theme.of(context);
    final meta = [
      r.code,
      if (r.apartmentCode != null) 'Căn ${r.apartmentCode}',
      r.category.label,
      if (showAssignee && r.assignedStaffName != null) r.assignedStaffName!,
    ].join(' · ');
    final time = r.deadline != null && r.status != RequestStatus.closed
        ? 'Hạn ${formatDateTime(r.deadline)}'
        : formatDateTime(r.createdAt);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          r.type == RequestType.repair
              ? Icons.build_outlined
              : Icons.report_outlined,
          size: 20,
        ),
      ),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RequestStatusChip(r.status),
                if (r.isOverdue) overdueChip,
                if (r.priority.index >= RequestPriority.high.index)
                  StatusChip(label: r.priority.label, tone: r.priority.tone),
                Text(time, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dải ảnh đã upload (bấm để xem lớn).
class NetworkImageStrip extends StatelessWidget {
  const NetworkImageStrip(this.urls, {super.key});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final url = mediaUrl(urls[i]);
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  Dialog(child: InteractiveViewer(child: Image.network(url))),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.square(
                  dimension: 88,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Chọn tối đa [max] ảnh JPEG/PNG từ thư viện, trả về qua [onChanged] dạng [UploadFile].
class ImagePickerField extends StatefulWidget {
  const ImagePickerField({
    super.key,
    required this.onChanged,
    this.field = 'images',
    this.max = 5,
  });

  final ValueChanged<List<UploadFile>> onChanged;
  final String field;
  final int max;

  @override
  State<ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends State<ImagePickerField> {
  final _files = <UploadFile>[];

  Future<void> _pick() async {
    try {
      final remaining = widget.max - _files.length;
      final picker = ImagePicker();
      // pickMultiImage yêu cầu limit >= 2; còn 1 chỗ thì chọn đơn
      final picked = remaining >= 2
          ? await picker.pickMultiImage(
              imageQuality: 80,
              maxWidth: 1920,
              limit: remaining,
            )
          : [
              ?await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 80,
                maxWidth: 1920,
              ),
            ];
      for (final x in picked.take(remaining)) {
        final name = x.name.toLowerCase().endsWith('.png')
            ? x.name
            : '${x.name}.jpg';
        _files.add(
          UploadFile(
            field: widget.field,
            filename: name,
            bytes: await x.readAsBytes(),
          ),
        );
      }
      setState(() {});
      widget.onChanged(List.of(_files));
    } catch (e) {
      if (mounted) showSnack(context, 'Không chọn được ảnh', error: true);
    }
  }

  void _remove(int i) {
    setState(() => _files.removeAt(i));
    widget.onChanged(List.of(_files));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _files.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(_files[i].bytes),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => _remove(i),
                      child: const CircleAvatar(
                        radius: 11,
                        child: Icon(Icons.close, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            if (_files.length < widget.max)
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Thêm ảnh (${_files.length}/${widget.max})'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Hộp thoại nhập lý do bắt buộc. Trả null khi hủy.
Future<String?> reasonDialog(
  BuildContext context, {
  required String title,
  String label = 'Lý do',
  String confirmText = 'Xác nhận',
  bool destructive = false,
}) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
          validator: (v) =>
              (v ?? '').trim().length < 3 ? 'Tối thiểu 3 ký tự' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: Text(confirmText),
        ),
      ],
    ),
  );
}
