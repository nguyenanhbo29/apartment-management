import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/app_user.dart';
import '../../staff/data/staff_repository.dart';
import '../../staff/presentation/staff_picker.dart';
import '../application/service_requests_providers.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';

/// UC-30: Phân công / chuyển người (Manager): bộ phận → nhân viên (kèm tải việc) → hạn xử lý.
class AssignRequestPage extends ConsumerStatefulWidget {
  const AssignRequestPage({
    super.key,
    required this.requestId,
    this.reassign = false,
  });

  final String requestId;
  final bool reassign;

  @override
  ConsumerState<AssignRequestPage> createState() => _AssignRequestPageState();
}

class _AssignRequestPageState extends ConsumerState<AssignRequestPage> {
  final _note = TextEditingController();
  Department? _department;
  StaffMember? _staff;
  RequestPriority? _priority;
  late DateTime _deadline;
  bool _initialized = false;
  bool _saving = false;

  /// Danh mục -> bộ phận gợi ý.
  static const _suggest = {
    RequestCategory.security: Department.security,
    RequestCategory.noise: Department.security,
    RequestCategory.service: Department.reception,
    RequestCategory.hygiene: Department.facility,
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _init(ServiceRequest r) {
    if (_initialized) return;
    _initialized = true;
    _department = r.department ?? _suggest[r.category] ?? Department.technical;
    _priority = r.priority;
    final now = DateTime.now();
    final keep = r.deadline != null && r.deadline!.isAfter(now);
    _deadline = keep
        ? r.deadline!
        : DateTime(now.year, now.month, now.day + 2, 17);
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _submit(ServiceRequest r) async {
    if (_staff == null) {
      return showSnack(context, 'Chọn nhân viên xử lý', error: true);
    }
    if (!_deadline.isAfter(DateTime.now())) {
      return showSnack(context, 'Hạn xử lý phải ở tương lai', error: true);
    }
    if (widget.reassign && _note.text.trim().length < 3) {
      return showSnack(
        context,
        'Nhập lý do chuyển người (tối thiểu 3 ký tự)',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(serviceRequestsRepositoryProvider)
          .assign(
            r.id,
            department: _department!,
            staffId: _staff!.user.id,
            deadline: _deadline,
            priority: _priority,
            note: _note.text,
            reassign: widget.reassign,
          );
      if (!mounted) return;
      showSnack(
        context,
        widget.reassign ? 'Đã chuyển người xử lý' : 'Đã phân công',
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
    final async = ref.watch(requestDetailProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reassign ? 'Chuyển người xử lý' : 'Phân công'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(requestDetailProvider(widget.requestId)),
        ),
        data: (r) {
          _init(r);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${r.code} · ${r.title}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Department>(
                      initialValue: _department,
                      decoration: const InputDecoration(labelText: 'Bộ phận'),
                      items: [
                        for (final d in Department.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (d) => setState(() {
                        _department = d;
                        _staff = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('Hạn xử lý'),
                      subtitle: Text(formatDateTime(_deadline)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: _pickDeadline,
                    ),
                    if (!widget.reassign)
                      DropdownButtonFormField<RequestPriority>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Mức độ ưu tiên',
                        ),
                        items: [
                          for (final p in RequestPriority.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (p) => setState(() => _priority = p),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: widget.reassign
                            ? 'Lý do chuyển người'
                            : 'Ghi chú nội bộ (không bắt buộc)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nhân viên',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    StaffPicker(
                      key: ValueKey(_department),
                      department: _department!,
                      excludeId: widget.reassign ? r.assignedStaffId : null,
                      selectedId: _staff?.user.id,
                      onSelected: (s) => setState(() => _staff = s),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: LoadingButton(
                      loading: _saving,
                      onPressed: () => _submit(r),
                      label: widget.reassign ? 'Chuyển người' : 'Phân công',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
