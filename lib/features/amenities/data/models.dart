import '../../../core/utils/json.dart';
import '../../../core/widgets/status_chip.dart';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class Amenity {
  const Amenity({
    required this.id,
    required this.name,
    required this.openTime,
    required this.closeTime,
    required this.slotDuration,
    required this.capacity,
    required this.requiresApproval,
    required this.cancelDeadlineHours,
    required this.isActive,
    this.description,
    this.rules,
    this.location,
  });

  final String id;
  final String name;
  final String openTime;
  final String closeTime;
  final int slotDuration;
  final int capacity;
  final bool requiresApproval;
  final int cancelDeadlineHours;
  final bool isActive;
  final String? description;
  final String? rules;
  final String? location;

  factory Amenity.fromJson(Map<String, dynamic> j) => Amenity(
    id: j['_id'] as String,
    name: j['name'] as String? ?? '',
    openTime: j['openTime'] as String? ?? '',
    closeTime: j['closeTime'] as String? ?? '',
    slotDuration: intOf(j['slotDuration']) ?? 60,
    capacity: intOf(j['capacity']) ?? 1,
    requiresApproval: j['requiresApproval'] == true,
    cancelDeadlineHours: intOf(j['cancelDeadlineHours']) ?? 0,
    isActive: j['status'] != 'inactive',
    description: j['description'] as String?,
    rules: j['rules'] as String?,
    location: j['location'] as String?,
  );
}

class SlotInfo {
  const SlotInfo({
    required this.start,
    required this.end,
    required this.remaining,
    required this.available,
  });

  final DateTime start;
  final DateTime end;
  final int remaining;
  final bool available;

  /// 'HH:mm' theo giờ máy (gửi lên làm startTime; máy ở VN nên trùng giờ VN).
  String get startLabel => hhmm(start);
  String get label => '${hhmm(start)}–${hhmm(end)}';

  factory SlotInfo.fromJson(Map<String, dynamic> j) => SlotInfo(
    start: dateOf(j['start'])!,
    end: dateOf(j['end'])!,
    remaining: intOf(j['remaining']) ?? 0,
    available: j['available'] == true,
  );
}

enum BookingStatus {
  pending('Chờ duyệt', StatusTone.info),
  confirmed('Đã xác nhận', StatusTone.success),
  rejected('Bị từ chối', StatusTone.danger),
  cancelled('Đã hủy', StatusTone.neutral),
  completed('Đã sử dụng', StatusTone.neutral);

  const BookingStatus(this.label, this.tone);
  final String label;
  final StatusTone tone;

  static BookingStatus parse(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => pending);
}

class AmenityBooking {
  const AmenityBooking({
    required this.id,
    required this.status,
    required this.numberOfParticipants,
    this.amenityId,
    this.amenityName,
    this.amenityLocation,
    this.apartmentCode,
    this.bookedByName,
    this.bookedByPhone,
    this.startTime,
    this.endTime,
    this.note,
    this.rejectReason,
    this.cancelReason,
    this.cancelDeadline,
    this.reviewedByName,
    this.cancelledByStaff = false,
    this.allowedActions = const {},
  });

  final String id;
  final BookingStatus status;
  final int numberOfParticipants;
  final String? amenityId;
  final String? amenityName;
  final String? amenityLocation;
  final String? apartmentCode;
  final String? bookedByName;
  final String? bookedByPhone;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? note;
  final String? rejectReason;
  final String? cancelReason;
  final DateTime? cancelDeadline;
  final String? reviewedByName;

  /// Bị ban quản lý hủy (sự cố) chứ không phải cư dân tự hủy.
  final bool cancelledByStaff;

  /// Chỉ có ở API chi tiết: approve, reject, cancel, cancel-by-staff.
  final Set<String> allowedActions;

  String get timeLabel => startTime == null || endTime == null
      ? ''
      : '${hhmm(startTime!)}–${hhmm(endTime!)}';

  factory AmenityBooking.fromJson(Map<String, dynamic> j) {
    final (amenityId, amenity) = refOf(j['amenityId']);
    final (_, apt) = refOf(j['apartmentId']);
    final (_, booker) = refOf(j['bookedBy']);
    final (_, reviewer) = refOf(j['reviewedBy']);
    return AmenityBooking(
      id: j['_id'] as String,
      status: BookingStatus.parse(j['status'] as String?),
      numberOfParticipants: intOf(j['numberOfParticipants']) ?? 1,
      amenityId: amenityId,
      amenityName: amenity?['name'] as String?,
      amenityLocation: amenity?['location'] as String?,
      apartmentCode: apt?['code'] as String?,
      bookedByName: booker?['fullName'] as String?,
      bookedByPhone: booker?['phone'] as String?,
      startTime: dateOf(j['startTime']),
      endTime: dateOf(j['endTime']),
      note: j['note'] as String?,
      rejectReason: j['rejectReason'] as String?,
      cancelReason: j['cancelReason'] as String?,
      cancelDeadline: dateOf(j['cancelDeadline']),
      reviewedByName: reviewer?['fullName'] as String?,
      cancelledByStaff: j['cancelledByStaff'] == true,
      allowedActions: stringsOf(j['allowedActions']).toSet(),
    );
  }
}
