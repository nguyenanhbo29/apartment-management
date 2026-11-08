import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../auth/data/app_user.dart';
import 'models.dart';

/// Bộ lọc hàng chờ của Manager. `status == null` + `overdue == false` = tất cả.
class QueueFilter {
  const QueueFilter({
    this.status = RequestStatus.pending,
    this.overdue = false,
  });

  final RequestStatus? status;
  final bool overdue;

  Map<String, dynamic> toQuery() => {
    'status': overdue || status == null ? 'all' : status!.api,
    if (overdue) 'overdue': 'true',
  };
}

/// M5 — Phiếu yêu cầu / phản ánh (UC-27 → 34).
class ServiceRequestsRepository {
  ServiceRequestsRepository(this._api);
  final ApiClient _api;

  static const _base = '/service-requests';
  static const _limit = 20;

  Future<ServiceRequest> create({
    required String apartmentId,
    required RequestType type,
    required RequestCategory category,
    required RequestPriority priority,
    required String title,
    required String description,
    List<UploadFile> images = const [],
  }) async => ServiceRequest.fromJson(
    await _api.multipart<Map<String, dynamic>>(
      'POST',
      _base,
      fields: {
        'apartmentId': apartmentId,
        'requestType': type.name,
        'category': category.name,
        'priority': priority.name,
        'title': title,
        'description': description,
      },
      files: images,
    ),
  );

  Future<Paged<ServiceRequest>> listMine({
    RequestStatus? status,
    int page = 1,
  }) => _api.getPaged(
    '$_base/mine',
    ServiceRequest.fromJson,
    query: {'status': ?status?.api, 'page': page, 'limit': _limit},
  );

  Future<Paged<ServiceRequest>> queue({
    QueueFilter filter = const QueueFilter(),
    int page = 1,
  }) => _api.getPaged(
    _base,
    ServiceRequest.fromJson,
    query: {...filter.toQuery(), 'page': page, 'limit': _limit},
  );

  // Việc của tôi (phiếu + nhiệm vụ): TasksRepository.assignments (features/tasks)

  Future<ServiceRequest> get(String id) async => ServiceRequest.fromJson(
    await _api.get<Map<String, dynamic>>('$_base/$id'),
  );

  Future<ServiceRequest> _patch(
    String id,
    String action, [
    Map<String, dynamic>? body,
  ]) async => ServiceRequest.fromJson(
    await _api.patch<Map<String, dynamic>>(
      '$_base/$id/$action',
      body: body ?? const {},
    ),
  );

  Future<ServiceRequest> reject(String id, String reason) =>
      _patch(id, 'reject', {'reason': reason});

  Future<ServiceRequest> assign(
    String id, {
    required Department department,
    required String staffId,
    required DateTime deadline,
    RequestPriority? priority,
    String? note,
    bool reassign = false,
  }) => _patch(id, reassign ? 'reassign' : 'assign', {
    'department': department.name,
    'staffId': staffId,
    'deadline': deadline.toUtc().toIso8601String(),
    if (!reassign && priority != null) 'priority': priority.name,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });

  Future<ServiceRequest> start(String id) => _patch(id, 'start');

  Future<ServiceRequest> finish(
    String id,
    String note, {
    List<UploadFile> images = const [],
  }) async => ServiceRequest.fromJson(
    await _api.multipart<Map<String, dynamic>>(
      'PATCH',
      '$_base/$id/finish',
      fields: {'note': note},
      files: images,
    ),
  );

  Future<ServiceRequest> confirm(String id, int rating, {String? feedback}) =>
      _patch(id, 'confirm', {
        'rating': rating,
        if (feedback != null && feedback.trim().isNotEmpty)
          'feedback': feedback.trim(),
      });

  Future<ServiceRequest> reopen(String id, String reason) =>
      _patch(id, 'reopen', {'reason': reason});
}

final serviceRequestsRepositoryProvider = Provider<ServiceRequestsRepository>(
  (ref) => ServiceRequestsRepository(ref.watch(apiClientProvider)),
);
