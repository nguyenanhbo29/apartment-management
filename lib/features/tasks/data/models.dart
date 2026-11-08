import '../../../core/utils/json.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/app_user.dart';
import '../../service_requests/data/models.dart';

enum TaskStatus {
  assigned('assigned', 'Đã giao', StatusTone.info),
  inProgress('in_progress', 'Đang làm', StatusTone.warning),
  completed('completed', 'Hoàn thành', StatusTone.success),
  cancelled('cancelled', 'Đã hủy', StatusTone.neutral);

  const TaskStatus(this.api, this.label, this.tone);
  final String api;
  final String label;
  final StatusTone tone;

  static TaskStatus parse(String? v) =>
      values.firstWhere((e) => e.api == v, orElse: () => assigned);
}

enum TaskCategory {
  inspection('Kiểm tra định kỳ'),
  maintenance('Bảo trì'),
  cleaning('Vệ sinh'),
  patrol('Tuần tra'),
  other('Khác');

  const TaskCategory(this.label);
  final String label;

  static TaskCategory parse(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => other);
}

/// Hành động (trùng tên với backend `allowedActions` và route).
enum TaskAction {
  start('Bắt đầu'),
  complete('Hoàn thành'),
  reassign('Chuyển người'),
  cancel('Hủy nhiệm vụ');

  const TaskAction(this.label);
  final String label;

  static TaskAction? tryParse(String? v) {
    for (final a in values) {
      if (a.name == v) return a;
    }
    return null;
  }
}

const _taskActionLabels = {
  'created': 'Tạo và giao việc',
  'reassign': 'Chuyển người',
  'start': 'Bắt đầu',
  'complete': 'Hoàn thành',
  'cancel': 'Hủy nhiệm vụ',
};

String taskActionLabel(String action) => _taskActionLabels[action] ?? action;

class OperationalTask {
  const OperationalTask({
    required this.id,
    required this.code,
    required this.title,
    required this.category,
    required this.priority,
    required this.status,
    required this.isOverdue,
    this.description,
    this.location,
    this.department,
    this.assignedStaffId,
    this.assignedStaffName,
    this.assignedStaffPhone,
    this.createdByName,
    this.deadline,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.completionNote,
    this.resultImages = const [],
    this.cancelReason,
    this.timeline = const [],
    this.allowedActions = const {},
  });

  final String id;
  final String code;
  final String title;
  final TaskCategory category;
  final RequestPriority priority;
  final TaskStatus status;
  final bool isOverdue;
  final String? description;
  final String? location;
  final Department? department;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final String? assignedStaffPhone;
  final String? createdByName;
  final DateTime? deadline;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? completionNote;
  final List<String> resultImages;
  final String? cancelReason;

  /// Chỉ có ở API chi tiết.
  final List<TimelineEntry> timeline;
  final Set<TaskAction> allowedActions;

  factory OperationalTask.fromJson(Map<String, dynamic> j) {
    final (staffId, staff) = refOf(j['assignedStaffId']);
    final (_, creator) = refOf(j['createdBy']);
    return OperationalTask(
      id: j['_id'] as String,
      code: j['taskCode'] as String? ?? '',
      title: j['title'] as String? ?? '',
      category: TaskCategory.parse(j['category'] as String?),
      priority: RequestPriority.parse(j['priority'] as String?),
      status: TaskStatus.parse(j['status'] as String?),
      isOverdue: j['isOverdue'] == true,
      description: j['description'] as String?,
      location: j['location'] as String?,
      department: Department.parse(j['department'] as String?),
      assignedStaffId: staffId,
      assignedStaffName: staff?['fullName'] as String?,
      assignedStaffPhone: staff?['phone'] as String?,
      createdByName: creator?['fullName'] as String?,
      deadline: dateOf(j['deadline']),
      createdAt: dateOf(j['createdAt']),
      startedAt: dateOf(j['startedAt']),
      completedAt: dateOf(j['completedAt']),
      completionNote: j['completionNote'] as String?,
      resultImages: stringsOf(j['resultImages']),
      cancelReason: j['cancelReason'] as String?,
      timeline: ((j['timeline'] as List?) ?? const [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      allowedActions: stringsOf(j['allowedActions'])
          .map(TaskAction.tryParse)
          .whereType<TaskAction>()
          .toSet(),
    );
  }
}

/// Một mục trong "Việc của tôi": phiếu (M5) hoặc nhiệm vụ (M7).
sealed class AssignmentItem {
  const AssignmentItem();

  factory AssignmentItem.fromJson(Map<String, dynamic> j) => j['kind'] == 'task'
      ? TaskAssignment(OperationalTask.fromJson(j))
      : RequestAssignment(ServiceRequest.fromJson(j));
}

class RequestAssignment extends AssignmentItem {
  const RequestAssignment(this.request);
  final ServiceRequest request;
}

class TaskAssignment extends AssignmentItem {
  const TaskAssignment(this.task);
  final OperationalTask task;
}
