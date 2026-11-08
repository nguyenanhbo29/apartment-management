import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../auth/data/app_user.dart';
import '../../service_requests/data/models.dart';
import 'models.dart';

enum AssignmentTab {
  active('Đang làm'),
  overdue('Quá hạn'),
  done('Đã xong');

  const AssignmentTab(this.label);
  final String label;
}

/// Bộ lọc danh sách nhiệm vụ. `overdue` ưu tiên hơn `status`.
class TaskFilter {
  const TaskFilter({this.status, this.overdue = false});
  final TaskStatus? status;
  final bool overdue;
}

/// M7 — Nhiệm vụ vận hành (UC-41, 42) + Việc của tôi (UC-31).
class TasksRepository {
  TasksRepository(this._api);
  final ApiClient _api;

  static const _base = '/tasks';

  Future<OperationalTask> create({
    required String title,
    String? description,
    required TaskCategory category,
    String? location,
    required RequestPriority priority,
    required Department department,
    required String staffId,
    required DateTime deadline,
  }) async => OperationalTask.fromJson(
    await _api.post<Map<String, dynamic>>(
      _base,
      body: {
        'title': title.trim(),
        if ((description ?? '').trim().isNotEmpty)
          'description': description!.trim(),
        'category': category.name,
        if ((location ?? '').trim().isNotEmpty) 'location': location!.trim(),
        'priority': priority.name,
        'department': department.name,
        'staffId': staffId,
        'deadline': deadline.toUtc().toIso8601String(),
      },
    ),
  );

  /// Manager: mọi nhiệm vụ. Staff: backend luôn trả nhiệm vụ của chính mình (UC-42).
  Future<Paged<OperationalTask>> list({
    TaskFilter filter = const TaskFilter(),
    int page = 1,
  }) => _api.getPaged(
    _base,
    OperationalTask.fromJson,
    query: {
      if (filter.overdue) 'overdue': 'true',
      if (!filter.overdue && filter.status != null)
        'status': filter.status!.api,
      'page': page,
      'limit': 20,
    },
  );

  Future<OperationalTask> get(String id) async => OperationalTask.fromJson(
    await _api.get<Map<String, dynamic>>('$_base/$id'),
  );

  Future<OperationalTask> _patch(
    String id,
    String action, [
    Object? body,
  ]) async => OperationalTask.fromJson(
    await _api.patch<Map<String, dynamic>>('$_base/$id/$action', body: body),
  );

  Future<OperationalTask> start(String id) => _patch(id, 'start');

  Future<OperationalTask> complete(
    String id, {
    String? note,
    List<UploadFile> images = const [],
  }) async => OperationalTask.fromJson(
    await _api.multipart<Map<String, dynamic>>(
      'PATCH',
      '$_base/$id/complete',
      fields: {'note': (note ?? '').trim().isEmpty ? null : note!.trim()},
      files: images,
    ),
  );

  Future<OperationalTask> reassign(
    String id, {
    required Department department,
    required String staffId,
    DateTime? deadline,
    required String note,
  }) => _patch(id, 'reassign', {
    'department': department.name,
    'staffId': staffId,
    if (deadline != null) 'deadline': deadline.toUtc().toIso8601String(),
    'note': note.trim(),
  });

  Future<OperationalTask> cancel(String id, String reason) =>
      _patch(id, 'cancel', {'reason': reason});

  /// UC-31: phiếu + nhiệm vụ đang giao cho tôi.
  Future<Paged<AssignmentItem>> assignments({
    AssignmentTab tab = AssignmentTab.active,
    int page = 1,
  }) => _api.getPaged(
    '/me/assignments',
    AssignmentItem.fromJson,
    query: {'tab': tab.name, 'page': page, 'limit': 20},
  );
}

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(apiClientProvider)),
);

final taskDetailProvider = FutureProvider.autoDispose
    .family<OperationalTask, String>(
      (ref, id) => ref.watch(tasksRepositoryProvider).get(id),
    );
