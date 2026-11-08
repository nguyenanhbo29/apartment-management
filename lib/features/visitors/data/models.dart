import '../../../core/utils/json.dart';
import '../../../core/widgets/status_chip.dart';

enum VisitorStatus {
  expected('expected', 'Chờ khách đến', StatusTone.info),
  checkedIn('checked_in', 'Đang trong tòa nhà', StatusTone.success),
  checkedOut('checked_out', 'Đã ra về', StatusTone.neutral),
  cancelled('cancelled', 'Đã hủy', StatusTone.neutral);

  const VisitorStatus(this.api, this.label, this.tone);
  final String api;
  final String label;
  final StatusTone tone;

  static VisitorStatus parse(String? v) =>
      values.firstWhere((e) => e.api == v, orElse: () => expected);
}

/// Hành động (trùng tên với backend `allowedActions` và route).
abstract final class VisitorAction {
  static const cancel = 'cancel';
  static const checkIn = 'check-in';
  static const checkOut = 'check-out';
}

class Visitor {
  const Visitor({
    required this.id,
    required this.code,
    required this.visitorName,
    required this.numberOfPeople,
    required this.status,
    required this.isOverdue,
    this.visitorPhone,
    this.vehiclePlate,
    this.note,
    this.apartmentId,
    this.apartmentCode,
    this.createdByName,
    this.createdByPhone,
    this.timeFrom,
    this.timeTo,
    this.checkInTime,
    this.checkOutTime,
    this.checkedInByName,
    this.cancelReason,
    this.allowedActions = const {},
  });

  final String id;
  final String code;
  final String visitorName;
  final int numberOfPeople;
  final VisitorStatus status;
  final bool isOverdue;
  final String? visitorPhone;
  final String? vehiclePlate;
  final String? note;
  final String? apartmentId;
  final String? apartmentCode;
  final String? createdByName;
  final String? createdByPhone;
  final DateTime? timeFrom;
  final DateTime? timeTo;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? checkedInByName;
  final String? cancelReason;

  /// Chỉ có ở API chi tiết.
  final Set<String> allowedActions;

  factory Visitor.fromJson(Map<String, dynamic> j) {
    final (aptId, apt) = refOf(j['apartmentId']);
    final (_, creator) = refOf(j['createdBy']);
    final (_, checker) = refOf(j['checkedInBy']);
    return Visitor(
      id: j['_id'] as String,
      code: j['appointmentCode'] as String? ?? '',
      visitorName: j['visitorName'] as String? ?? '',
      numberOfPeople: intOf(j['numberOfPeople']) ?? 1,
      status: VisitorStatus.parse(j['status'] as String?),
      isOverdue: j['isOverdue'] == true,
      visitorPhone: j['visitorPhone'] as String?,
      vehiclePlate: j['vehiclePlate'] as String?,
      note: j['note'] as String?,
      apartmentId: aptId,
      apartmentCode: apt?['code'] as String?,
      createdByName: creator?['fullName'] as String?,
      createdByPhone: creator?['phone'] as String?,
      timeFrom: dateOf(j['timeFrom']),
      timeTo: dateOf(j['timeTo']),
      checkInTime: dateOf(j['checkInTime']),
      checkOutTime: dateOf(j['checkOutTime']),
      checkedInByName: checker?['fullName'] as String?,
      cancelReason: j['cancelReason'] as String?,
      allowedActions: stringsOf(j['allowedActions']).toSet(),
    );
  }
}
