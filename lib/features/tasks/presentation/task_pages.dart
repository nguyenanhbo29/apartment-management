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
import '../../auth/application/auth_controller.dart';
import '../../auth/data/app_user.dart';
import '../../service_requests/data/models.dart';
import '../../service_requests/presentation/widgets.dart'
    show RequestTile, overdueChip;
import '../../staff/data/staff_repository.dart';
import '../../staff/presentation/staff_picker.dart';
import '../data/models.dart';
import '../data/tasks_repository.dart';

/// Một dòng nhiệm vụ.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.showAssignee = false,
  });

  final OperationalTask task;
  final VoidCallback? onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final theme = Theme.of(context);
    final meta = [
      t.code,
      t.category.label,
      if ((t.location ?? '').isNotEmpty) t.location!,
      if (showAssignee && t.assignedStaffName != null) t.assignedStaffName!,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.tertiaryContainer,
        child: const Icon(Icons.task_alt, size: 20),
      ),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                const StatusChip(label: 'Nhiệm vụ', tone: StatusTone.neutral),
                StatusChip(label: t.status.label, tone: t.status.tone),
                if (t.isOverdue) overdueChip,
                if (t.priority.index >= RequestPriority.high.index)
                  StatusChip(label: t.priority.label, tone: t.priority.tone),
                Text(
                  'Hạn ${formatDateTime(t.deadline)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================== UC-31 Việc của tôi
/// Việc của tôi (Staff): phiếu yêu cầu + nhiệm vụ vận hành trong một danh sách.
class MyWorkPage extends ConsumerStatefulWidget {
  const MyWorkPage({super.key});

  @override
  ConsumerState<MyWorkPage> createState() => _MyWorkPageState();
}

class _MyWorkPageState extends ConsumerState<MyWorkPage> {
  int _reload = 0;

  Future<void> _open(String route) async {
    await context.push(route);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tasksRepositoryProvider);
    return DefaultTabController(
      length: AssignmentTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Việc của tôi'),
          actions: [
            IconButton(
              tooltip: 'Lịch sử nhiệm vụ',
              icon: const Icon(Icons.history),
              onPressed: () => _open('/tasks'),
            ),
          ],
          bottom: TabBar(
            tabs: [for (final t in AssignmentTab.values) Tab(text: t.label)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in AssignmentTab.values)
              PagedListView<AssignmentItem>(
                key: ValueKey('${t.name}|$_reload'),
                fetch: (page) => repo.assignments(tab: t, page: page),
                emptyText: t == AssignmentTab.overdue
                    ? 'Không có việc quá hạn'
                    : 'Không có việc',
                itemBuilder: (context, item) => switch (item) {
                  RequestAssignment(:final request) => RequestTile(
                    request: request,
                    onTap: () => _open('/requests/${request.id}'),
                  ),
                  TaskAssignment(:final task) => TaskTile(
                    task: task,
                    onTap: () => _open('/tasks/${task.id}'),
                  ),
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================== UC-41 / UC-42 danh sách
/// Manager: Nhiệm vụ vận hành (tạo, lọc). Staff: Lịch sử nhiệm vụ của mình.
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key, this.initial = const TaskFilter()});

  /// Bộ lọc ban đầu (dashboard mở sẵn "quá hạn").
  final TaskFilter initial;

  /// Từ query của route: ?filter=overdue | ?status=in_progress
  factory TasksPage.fromQuery(Map<String, String> q) => TasksPage(
    initial: switch ((q['filter'], q['status'])) {
      ('overdue', _) => const TaskFilter(overdue: true),
      (_, final String s) => TaskFilter(status: TaskStatus.parse(s)),
      _ => const TaskFilter(),
    },
  );

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  late TaskFilter _filter = widget.initial;
  int _reload = 0;

  static const _options = <(String, TaskFilter)>[
    ('Tất cả', TaskFilter()),
    ('Đã giao', TaskFilter(status: TaskStatus.assigned)),
    ('Đang làm', TaskFilter(status: TaskStatus.inProgress)),
    ('Quá hạn', TaskFilter(overdue: true)),
    ('Hoàn thành', TaskFilter(status: TaskStatus.completed)),
    ('Đã hủy', TaskFilter(status: TaskStatus.cancelled)),
  ];

  Future<void> _open(String route) async {
    await context.push(route);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tasksRepositoryProvider);
    final isManager = ref.watch(currentUserProvider)?.isManager ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(isManager ? 'Nhiệm vụ vận hành' : 'Lịch sử nhiệm vụ'),
      ),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _open('/tasks/new'),
              icon: const Icon(Icons.add_task),
              label: const Text('Giao nhiệm vụ'),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (label, f) in _options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected:
                          _filter.status == f.status &&
                          _filter.overdue == f.overdue,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<OperationalTask>(
              key: ValueKey(
                '${_filter.status?.api}|${_filter.overdue}|$_reload',
              ),
              fetch: (page) => repo.list(filter: _filter, page: page),
              emptyText: 'Không có nhiệm vụ',
              itemBuilder: (context, t) => TaskTile(
                task: t,
                showAssignee: isManager,
                onTap: () => _open('/tasks/${t.id}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================== UC-41 giao / chuyển người
/// Tạo nhiệm vụ ([taskId] null) hoặc chuyển người xử lý ([taskId] có).
class TaskFormPage extends ConsumerStatefulWidget {
  const TaskFormPage({super.key, this.taskId});
  final String? taskId;

  @override
  ConsumerState<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends ConsumerState<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _note = TextEditingController();
  TaskCategory _category = TaskCategory.inspection;
  RequestPriority _priority = RequestPriority.normal;
  Department _department = Department.technical;
  StaffMember? _staff;
  late DateTime _deadline;
  bool _deadlineChanged = false;
  bool _initialized = false;
  bool _saving = false;

  bool get _reassign => widget.taskId != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _deadline = DateTime(now.year, now.month, now.day + 1, 17);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _deadlineChanged = true;
    });
  }

  Future<void> _submit(OperationalTask? current) async {
    if (!_formKey.currentState!.validate()) return;
    if (_staff == null) {
      return showSnack(context, 'Chọn nhân viên phụ trách', error: true);
    }
    if ((!_reassign || _deadlineChanged) &&
        !_deadline.isAfter(DateTime.now())) {
      return showSnack(context, 'Hạn hoàn thành phải ở tương lai', error: true);
    }
    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    try {
      if (_reassign) {
        await repo.reassign(
          widget.taskId!,
          department: _department,
          staffId: _staff!.user.id,
          deadline: _deadlineChanged ? _deadline : null,
          note: _note.text,
        );
      } else {
        await repo.create(
          title: _title.text,
          description: _description.text,
          category: _category,
          location: _location.text,
          priority: _priority,
          department: _department,
          staffId: _staff!.user.id,
          deadline: _deadline,
        );
      }
      if (!mounted) return;
      showSnack(
        context,
        _reassign ? 'Đã chuyển người phụ trách' : 'Đã giao nhiệm vụ',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form(OperationalTask? current) => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (current != null) ...[
          Text(
            '${current.code} · ${current.title}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (current.assignedStaffName != null)
            Text('Đang giao cho: ${current.assignedStaffName}'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Lý do chuyển người'),
            validator: (v) =>
                (v ?? '').trim().length < 3 ? 'Tối thiểu 3 ký tự' : null,
          ),
        ] else ...[
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề',
              hintText: 'VD: Kiểm tra bình chữa cháy tầng 1–5',
            ),
            validator: (v) => (v ?? '').trim().length < 3
                ? 'Tiêu đề tối thiểu 3 ký tự'
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TaskCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Loại nhiệm vụ'),
            items: [
              for (final c in TaskCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Khu vực'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Mô tả công việc'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<RequestPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Mức độ ưu tiên'),
            items: [
              for (final p in RequestPriority.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _priority = v ?? _priority),
          ),
        ],
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Hạn hoàn thành'),
          subtitle: Text(
            _reassign && !_deadlineChanged
                ? 'Giữ hạn cũ (${formatDateTime(current?.deadline)})'
                : formatDateTime(_deadline),
          ),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDeadline,
        ),
        DropdownButtonFormField<Department>(
          initialValue: _department,
          decoration: const InputDecoration(labelText: 'Bộ phận'),
          items: [
            for (final d in Department.values)
              DropdownMenuItem(value: d, child: Text(d.label)),
          ],
          onChanged: (d) => setState(() {
            _department = d ?? _department;
            _staff = null;
          }),
        ),
        const SizedBox(height: 16),
        Text('Người phụ trách', style: Theme.of(context).textTheme.titleSmall),
        StaffPicker(
          key: ValueKey(_department),
          department: _department,
          excludeId: current?.assignedStaffId,
          selectedId: _staff?.user.id,
          onSelected: (s) => setState(() => _staff = s),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          loading: _saving,
          onPressed: () => _submit(current),
          label: _reassign ? 'Chuyển người' : 'Giao nhiệm vụ',
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: () =>
          _title.text.trim().isNotEmpty ||
          _description.text.trim().isNotEmpty ||
          _location.text.trim().isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _staff != null,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_reassign ? 'Chuyển người phụ trách' : 'Giao nhiệm vụ'),
        ),
        body: !_reassign
            ? _form(null)
            : ref
                  .watch(taskDetailProvider(widget.taskId!))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorView(error: e),
                    data: (t) {
                      // Lần đầu: mặc định bộ phận hiện tại của nhiệm vụ
                      if (!_initialized) {
                        _initialized = true;
                        _department = t.department ?? _department;
                      }
                      return _form(t);
                    },
                  ),
      ),
    );
  }
}

// ======================================================================== UC-42 chi tiết
class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  bool _busy = false;

  TasksRepository get _repo => ref.read(tasksRepositoryProvider);
  void _reload() => ref.invalidate(taskDetailProvider(widget.taskId));

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
              ? 'Nhiệm vụ đã thay đổi, đã tải lại'
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

  Future<void> _onAction(TaskAction action, OperationalTask t) async {
    switch (action) {
      case TaskAction.start:
        final ok = await confirmDialog(
          context,
          title: 'Bắt đầu',
          message: 'Bắt đầu thực hiện ${t.code}?',
        );
        if (ok) await _run(() => _repo.start(t.id), 'Đã chuyển sang đang làm');
      case TaskAction.complete:
        final result = await _completeSheet();
        if (result != null) {
          await _run(
            () => _repo.complete(t.id, note: result.$1, images: result.$2),
            'Đã báo hoàn thành',
          );
        }
      case TaskAction.reassign:
        final done = await context.push<bool>('/tasks/${t.id}/reassign');
        if (done == true) _reload();
      case TaskAction.cancel:
        final reason = await reasonDialog(
          context,
          title: 'Hủy nhiệm vụ',
          confirmText: 'Hủy nhiệm vụ',
          destructive: true,
        );
        if (reason != null) {
          await _run(() => _repo.cancel(t.id, reason), 'Đã hủy nhiệm vụ');
        }
    }
  }

  Future<(String, List<UploadFile>)?> _completeSheet() {
    final note = TextEditingController();
    var images = <UploadFile>[];
    return showModalBottomSheet<(String, List<UploadFile>)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          // Chừa thanh điều hướng hệ thống (gesture bar) và bàn phím
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hoàn thành nhiệm vụ',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Kết quả (không bắt buộc)',
              ),
            ),
            const SizedBox(height: 12),
            ImagePickerField(onChanged: (f) => images = f),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (note.text, images)),
              child: const Text('Gửi'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    final t = async.value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t?.code ?? 'Nhiệm vụ')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: _reload),
        data: (t) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 6,
              children: [
                StatusChip(label: t.status.label, tone: t.status.tone),
                if (t.isOverdue) overdueChip,
              ],
            ),
            const SizedBox(height: 8),
            Text(t.title, style: theme.textTheme.titleLarge),
            if ((t.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.description!),
            ],
            const Divider(height: 32),
            InfoRow(
              label: 'Loại',
              value: t.category.label,
              icon: Icons.category_outlined,
            ),
            if ((t.location ?? '').isNotEmpty)
              InfoRow(
                label: 'Khu vực',
                value: t.location!,
                icon: Icons.place_outlined,
              ),
            InfoRow(
              label: 'Ưu tiên',
              value: t.priority.label,
              icon: Icons.flag_outlined,
            ),
            if (t.assignedStaffName != null)
              InfoRow(
                label: 'Phụ trách',
                value: [
                  t.assignedStaffName!,
                  if (t.department != null) t.department!.label,
                  if (t.assignedStaffPhone != null) t.assignedStaffPhone!,
                ].join(' · '),
                icon: Icons.engineering_outlined,
              ),
            InfoRow(
              label: 'Hạn',
              value: formatDateTime(t.deadline),
              icon: Icons.schedule,
            ),
            if (t.createdByName != null)
              InfoRow(
                label: 'Người giao',
                value: t.createdByName!,
                icon: Icons.person_outline,
              ),
            if (t.completedAt != null)
              InfoRow(
                label: 'Hoàn thành',
                value: formatDateTime(t.completedAt),
                icon: Icons.task_alt,
              ),
            if ((t.completionNote ?? '').isNotEmpty)
              InfoRow(
                label: 'Kết quả',
                value: t.completionNote!,
                icon: Icons.notes,
              ),
            if ((t.cancelReason ?? '').isNotEmpty)
              InfoRow(
                label: 'Lý do hủy',
                value: t.cancelReason!,
                icon: Icons.info_outline,
              ),
            if (t.resultImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              NetworkImageStrip(t.resultImages),
            ],
            const Divider(height: 32),
            Text('Lịch sử', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final h in t.timeline)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
                title: Text(taskActionLabel(h.action)),
                subtitle: Text(
                  [
                    '${h.actorName ?? 'Hệ thống'} · ${formatDateTime(h.createdAt)}',
                    if (h.assignedStaffName != null)
                      'Giao cho ${h.assignedStaffName}',
                    if ((h.note ?? '').isNotEmpty) h.note!,
                  ].join('\n'),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: t == null || t.allowedActions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _busy
                    ? const LinearProgressIndicator()
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final a in TaskAction.values.where(
                            t.allowedActions.contains,
                          ))
                            a == TaskAction.cancel || a == TaskAction.reassign
                                ? OutlinedButton(
                                    onPressed: () => _onAction(a, t),
                                    child: Text(a.label),
                                  )
                                : FilledButton(
                                    onPressed: () => _onAction(a, t),
                                    child: Text(a.label),
                                  ),
                        ],
                      ),
              ),
            ),
    );
  }
}
