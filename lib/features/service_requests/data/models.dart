import '../../../core/widgets/status_chip.dart';
import '../../auth/data/app_user.dart';

T _parse<T extends Enum>(
  List<T> values,
  String Function(T) api,
  String? v,
  T fallback,
) {
  for (final e in values) {
    if (api(e) == v) return e;
  }
  return fallback;
}

enum RequestType {
  repair('Sửa chữa'),
  complaint('Phản ánh');

  const RequestType(this.label);
  final String label;

  static RequestType parse(String? v) =>
      _parse(values, (e) => e.name, v, repair);

  /// Danh mục hợp lệ cho loại phiếu — giống REQUEST_CATEGORIES_BY_TYPE ở backend.
  /// Thang máy, vệ sinh, khác dùng cho cả hai loại.
  List<RequestCategory> get categories => switch (this) {
    repair => const [
      RequestCategory.electric,
      RequestCategory.plumbing,
      RequestCategory.internet,
      RequestCategory.elevator,
      RequestCategory.hygiene,
      RequestCategory.other,
    ],
    complaint => const [
      RequestCategory.elevator,
      RequestCategory.hygiene,
      RequestCategory.noise,
      RequestCategory.security,
      RequestCategory.service,
      RequestCategory.other,
    ],
  };
}

enum RequestCategory {
  electric('Điện'),
  plumbing('Cấp thoát nước'),
  internet('Internet / truyền hình'),
  elevator('Thang máy'),
  hygiene('Vệ sinh'),
  noise('Tiếng ồn'),
  security('An ninh'),
  service('Thái độ phục vụ'),
  other('Khác');

  const RequestCategory(this.label);
  final String label;

  static RequestCategory parse(String? v) =>
      _parse(values, (e) => e.name, v, other);
}

enum RequestPriority {
  low('Thấp', StatusTone.neutral),
  normal('Bình thường', StatusTone.neutral),
  high('Cao', StatusTone.warning),
  urgent('Khẩn cấp', StatusTone.danger);

  const RequestPriority(this.label, this.tone);
  final String label;
  final StatusTone tone;

  static RequestPriority parse(String? v) =>
      _parse(values, (e) => e.name, v, normal);
}

enum RequestStatus {
  pending('pending', 'Chờ tiếp nhận', StatusTone.info),
  rejected('rejected', 'Bị từ chối', StatusTone.danger),
  assigned('assigned', 'Đã phân công', StatusTone.info),
  inProgress('in_progress', 'Đang xử lý', StatusTone.warning),
  waitingConfirmation(
    'waiting_confirmation',
    'Chờ nghiệm thu',
    StatusTone.warning,
  ),
  reopened('reopened', 'Yêu cầu làm lại', StatusTone.danger),
  closed('closed', 'Đã đóng', StatusTone.success),
  cancelled('cancelled', 'Đã rút', StatusTone.neutral);

  const RequestStatus(this.api, this.label, this.tone);
  final String api;
  final String label;
  final StatusTone tone;

  static RequestStatus parse(String? v) =>
      _parse(values, (e) => e.api, v, pending);
}

/// Hành động đổi trạng thái, trùng tên với backend (`allowedActions`, `PATCH /:id/<action>`).
enum RequestAction {
  assign('Phân công'),
  reassign('Chuyển người'),
  reject('Từ chối'),
  start('Bắt đầu xử lý'),
  finish('Báo hoàn thành'),
  confirm('Nghiệm thu'),
  reopen('Yêu cầu làm lại'),
  cancel('Rút phiếu');

  const RequestAction(this.label);
  final String label;

  static RequestAction? tryParse(String? v) {
    for (final a in values) {
      if (a.name == v) return a;
    }
    return null;
  }
}

/// Trường populate có thể là object `{_id, ...}` hoặc chỉ id.
(String?, Map<String, dynamic>?) _ref(Object? v) => switch (v) {
  final Map<String, dynamic> m => (m['_id'] as String?, m),
  final String s => (s, null),
  _ => (null, null),
};

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
List<String> _strings(Object? v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

class TimelineEntry {
  const TimelineEntry({
    required this.action,
    required this.createdAt,
    this.actorName,
    this.newStatus,
    this.note,
    this.attachments = const [],
    this.assignedStaffName,
    this.deadline,
  });

  final String action;
  final DateTime? createdAt;
  final String? actorName;
  final RequestStatus? newStatus;
  final String? note;
  final List<String> attachments;
  final String? assignedStaffName;
  final DateTime? deadline;

  static const _labels = {
    'created': 'Tạo phiếu',
    'reject': 'Từ chối',
    'assign': 'Phân công',
    'reassign': 'Chuyển người xử lý',
    'start': 'Bắt đầu xử lý',
    'finish': 'Báo hoàn thành',
    'confirm': 'Nghiệm thu',
    'reopen': 'Yêu cầu làm lại',
    'cancel': 'Cư dân rút phiếu',
    'auto_closed': 'Tự đóng',
  };

  String get label => _labels[action] ?? action;

  factory TimelineEntry.fromJson(Map<String, dynamic> j) {
    final (_, actor) = _ref(j['updatedBy']);
    final (_, staff) = _ref(j['assignedStaffId']);
    return TimelineEntry(
      action: j['action'] as String,
      createdAt: _date(j['createdAt']),
      actorName: actor?['fullName'] as String?,
      newStatus: j['newStatus'] == null
          ? null
          : RequestStatus.parse(j['newStatus'] as String?),
      note: j['note'] as String?,
      attachments: _strings(j['attachments']),
      assignedStaffName: staff?['fullName'] as String?,
      deadline: _date(j['deadline']),
    );
  }
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.code,
    required this.type,
    required this.category,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.isOverdue,
    this.apartmentId,
    this.apartmentCode,
    this.createdById,
    this.createdByName,
    this.assignedStaffId,
    this.assignedStaffName,
    this.assignedStaffPhone,
    this.department,
    this.deadline,
    this.images = const [],
    this.resultNote,
    this.resultImages = const [],
    this.rejectReason,
    this.cancelReason,
    this.rating,
    this.feedback,
    this.reopenCount = 0,
    this.autoClosed = false,
    this.createdAt,
    this.closedAt,
    this.timeline = const [],
    this.allowedActions = const {},
  });

  final String id;
  final String code;
  final RequestType type;
  final RequestCategory category;
  final String title;
  final String description;
  final RequestPriority priority;
  final RequestStatus status;
  final bool isOverdue;
  final String? apartmentId;
  final String? apartmentCode;
  final String? createdById;
  final String? createdByName;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final String? assignedStaffPhone;
  final Department? department;
  final DateTime? deadline;
  final List<String> images;
  final String? resultNote;
  final List<String> resultImages;
  final String? rejectReason;
  final String? cancelReason;
  final int? rating;
  final String? feedback;
  final int reopenCount;
  final bool autoClosed;
  final DateTime? createdAt;
  final DateTime? closedAt;

  /// Chỉ có ở API chi tiết.
  final List<TimelineEntry> timeline;
  final Set<RequestAction> allowedActions;

  factory ServiceRequest.fromJson(Map<String, dynamic> j) {
    final (aptId, apt) = _ref(j['apartmentId']);
    final (creatorId, creator) = _ref(j['createdBy']);
    final (staffId, staff) = _ref(j['assignedStaffId']);
    return ServiceRequest(
      id: j['_id'] as String,
      code: j['requestCode'] as String? ?? '',
      type: RequestType.parse(j['requestType'] as String?),
      category: RequestCategory.parse(j['category'] as String?),
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      priority: RequestPriority.parse(j['priority'] as String?),
      status: RequestStatus.parse(j['status'] as String?),
      isOverdue: j['isOverdue'] == true,
      apartmentId: aptId,
      apartmentCode: apt?['code'] as String?,
      createdById: creatorId,
      createdByName: creator?['fullName'] as String?,
      assignedStaffId: staffId,
      assignedStaffName: staff?['fullName'] as String?,
      assignedStaffPhone: staff?['phone'] as String?,
      department: Department.parse(j['department'] as String?),
      deadline: _date(j['deadline']),
      images: _strings(j['images']),
      resultNote: j['resultNote'] as String?,
      resultImages: _strings(j['resultImages']),
      rejectReason: j['rejectReason'] as String?,
      cancelReason: j['cancelReason'] as String?,
      rating: (j['rating'] as num?)?.toInt(),
      feedback: j['feedback'] as String?,
      reopenCount: (j['reopenCount'] as num?)?.toInt() ?? 0,
      autoClosed: j['autoClosed'] == true,
      createdAt: _date(j['createdAt']),
      closedAt: _date(j['closedAt']),
      timeline: ((j['timeline'] as List?) ?? const [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      allowedActions: _strings(j['allowedActions'])
          .map(RequestAction.tryParse)
          .whereType<RequestAction>()
          .toSet(),
    );
  }
}
