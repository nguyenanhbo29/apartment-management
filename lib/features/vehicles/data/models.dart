import '../../../core/utils/json.dart';
import '../../../core/widgets/status_chip.dart';

enum VehicleType {
  motorbike('Xe máy'),
  car('Ô tô');

  const VehicleType(this.label);
  final String label;

  static VehicleType parse(String? v) => v == 'car' ? car : motorbike;
}

enum VehicleStatus {
  pending('Chờ duyệt', StatusTone.info),
  approved('Đã duyệt', StatusTone.success),
  rejected('Bị từ chối', StatusTone.danger),
  inactive('Ngừng sử dụng', StatusTone.neutral);

  const VehicleStatus(this.label, this.tone);
  final String label;
  final StatusTone tone;

  static VehicleStatus parse(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => pending);
}

/// Chuẩn hóa giống backend: '30a-123.45' -> '30A12345'.
String normalizePlate(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[\s.\-]'), '');

final plateRegex = RegExp(r'^[0-9]{2}[A-Z]{1,2}[0-9]{4,6}$');

/// Hiển thị dễ đọc: '30A12345' -> '30A-123.45', '29B1234' -> '29B-1234',
/// xe máy seri chữ + số: '29H155555' -> '29H1-555.55'.
String formatPlate(String plate) {
  final m = RegExp(r'^(\d{2}[A-Z]{1,2})(\d+)$').firstMatch(plate);
  if (m == null) return plate;
  var series = m.group(1)!;
  var digits = m.group(2)!;
  // 1 chữ cái + 6 số: số đầu thuộc seri xe máy (29-H1 555.55)
  if (series.length == 3 && digits.length == 6) {
    series += digits[0];
    digits = digits.substring(1);
  }
  final tail = digits.length == 5
      ? '${digits.substring(0, 3)}.${digits.substring(3)}'
      : digits;
  return '$series-$tail';
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.type,
    required this.plateNumber,
    required this.status,
    this.apartmentId,
    this.apartmentCode,
    this.ownerName,
    this.ownerPhone,
    this.brand,
    this.color,
    this.imageUrl,
    this.rejectReason,
    this.reviewedByName,
    this.reviewedAt,
    this.createdAt,
    this.deactivatedAt,
    this.allowedActions = const {},
  });

  final String id;
  final VehicleType type;
  final String plateNumber;
  final VehicleStatus status;
  final String? apartmentId;
  final String? apartmentCode;
  final String? ownerName;
  final String? ownerPhone;
  final String? brand;
  final String? color;
  final String? imageUrl;
  final String? rejectReason;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? deactivatedAt;

  /// Chỉ có ở API chi tiết: approve, reject, deactivate.
  final Set<String> allowedActions;

  String get displayPlate => formatPlate(plateNumber);

  factory Vehicle.fromJson(Map<String, dynamic> j) {
    final (aptId, apt) = refOf(j['apartmentId']);
    final (_, owner) = refOf(j['ownerId']);
    final (_, reviewer) = refOf(j['reviewedBy']);
    return Vehicle(
      id: j['_id'] as String,
      type: VehicleType.parse(j['type'] as String?),
      plateNumber: j['plateNumber'] as String? ?? '',
      status: VehicleStatus.parse(j['status'] as String?),
      apartmentId: aptId,
      apartmentCode: apt?['code'] as String?,
      ownerName: owner?['fullName'] as String?,
      ownerPhone: owner?['phone'] as String?,
      brand: j['brand'] as String?,
      color: j['color'] as String?,
      imageUrl: j['imageUrl'] as String?,
      rejectReason: j['rejectReason'] as String?,
      reviewedByName: reviewer?['fullName'] as String?,
      reviewedAt: dateOf(j['reviewedAt']),
      createdAt: dateOf(j['createdAt']),
      deactivatedAt: dateOf(j['deactivatedAt']),
      allowedActions: stringsOf(j['allowedActions']).toSet(),
    );
  }
}
