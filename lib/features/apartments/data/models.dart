import '../../../core/utils/formatters.dart';

enum ApartmentStatus {
  vacant('Trống'),
  occupied('Có người ở');

  const ApartmentStatus(this.label);
  final String label;

  static ApartmentStatus parse(String? v) =>
      v == 'occupied' ? ApartmentStatus.occupied : ApartmentStatus.vacant;
}

enum ResidentRelation {
  owner('Chủ hộ'),
  member('Thành viên'),
  tenant('Người thuê');

  const ResidentRelation(this.label);
  final String label;

  static ResidentRelation parse(String? v) =>
      ResidentRelation.values.firstWhere((e) => e.name == v, orElse: () => ResidentRelation.member);
}

enum ResidentStatus {
  pending('Chờ duyệt'),
  active('Đang ở'),
  rejected('Bị từ chối'),
  ended('Đã chuyển đi');

  const ResidentStatus(this.label);
  final String label;

  static ResidentStatus parse(String? v) =>
      ResidentStatus.values.firstWhere((e) => e.name == v, orElse: () => ResidentStatus.pending);
}

String? _id(Object? v) => v is Map ? v['_id']?.toString() : v?.toString();

class MyMembership {
  const MyMembership({required this.id, required this.relation, required this.isPayer});

  final String id;
  final ResidentRelation relation;
  final bool isPayer;

  bool get isOwner => relation == ResidentRelation.owner;

  factory MyMembership.fromJson(Map<String, dynamic> j) => MyMembership(
    id: j['id'].toString(),
    relation: ResidentRelation.parse(j['relation'] as String?),
    isPayer: j['isPayer'] == true,
  );
}

class Apartment {
  const Apartment({
    required this.id,
    required this.code,
    required this.floor,
    required this.area,
    required this.status,
    this.bedrooms,
    this.note,
    this.residentCount = 0,
    this.ownerName,
    this.myMembership,
  });

  final String id;
  final String code;
  final int floor;
  final double area;
  final int? bedrooms;
  final String? note;
  final ApartmentStatus status;
  final int residentCount;
  final String? ownerName;

  /// Vai trò của người đang xem trong căn hộ (chỉ có khi là Resident).
  final MyMembership? myMembership;

  factory Apartment.fromJson(Map<String, dynamic> j) => Apartment(
    id: j['_id'].toString(),
    code: j['code'] as String,
    floor: (j['floor'] as num).toInt(),
    area: (j['area'] as num).toDouble(),
    bedrooms: (j['bedrooms'] as num?)?.toInt(),
    note: j['note'] as String?,
    status: ApartmentStatus.parse(j['status'] as String?),
    residentCount: (j['residentCount'] as num?)?.toInt() ?? 0,
    ownerName: j['ownerName'] as String?,
    myMembership: j['myMembership'] is Map
        ? MyMembership.fromJson(j['myMembership'] as Map<String, dynamic>)
        : null,
  );
}

class ResidentRecord {
  const ResidentRecord({
    required this.id,
    required this.apartmentId,
    required this.fullName,
    required this.relation,
    required this.status,
    this.apartmentCode,
    this.userId,
    this.userEmail,
    this.phone,
    this.idNumber,
    this.dateOfBirth,
    this.isPayer = false,
    this.moveInDate,
    this.moveOutDate,
    this.moveOutReason,
    this.rejectReason,
    this.note,
    this.fromRegistration = false,
    this.registeredByName,
    this.createdAt,
  });

  final String id;
  final String apartmentId;
  final String? apartmentCode;
  final String? userId;
  final String? userEmail;
  final String fullName;
  final String? phone;
  final String? idNumber;
  final DateTime? dateOfBirth;
  final ResidentRelation relation;
  final ResidentStatus status;
  final bool isPayer;
  final DateTime? moveInDate;
  final DateTime? moveOutDate;
  final String? moveOutReason;
  final String? rejectReason;
  final String? note;
  final bool fromRegistration;
  final String? registeredByName;
  final DateTime? createdAt;

  bool get hasAccount => userId != null;

  factory ResidentRecord.fromJson(Map<String, dynamic> j) {
    final apt = j['apartmentId'];
    final user = j['userId'];
    final regBy = j['registeredBy'];
    return ResidentRecord(
      id: j['_id'].toString(),
      apartmentId: _id(apt)!,
      apartmentCode: apt is Map ? apt['code'] as String? : null,
      userId: _id(user),
      userEmail: user is Map ? user['email'] as String? : null,
      fullName: j['fullName'] as String,
      phone: j['phone'] as String?,
      idNumber: j['idNumber'] as String?,
      dateOfBirth: parseDate(j['dateOfBirth']),
      relation: ResidentRelation.parse(j['relation'] as String?),
      status: ResidentStatus.parse(j['status'] as String?),
      isPayer: j['isPayer'] == true,
      moveInDate: parseDate(j['moveInDate']),
      moveOutDate: parseDate(j['moveOutDate']),
      moveOutReason: j['moveOutReason'] as String?,
      rejectReason: j['rejectReason'] as String?,
      note: j['note'] as String?,
      fromRegistration: j['source'] == 'registration',
      registeredByName: regBy is Map ? regBy['fullName'] as String? : null,
      createdAt: parseDate(j['createdAt']),
    );
  }
}

/// Dữ liệu form hồ sơ cư trú (UC-08 thêm/sửa, UC-09 khai báo).
class ResidentInput {
  const ResidentInput({
    required this.fullName,
    required this.relation,
    this.phone,
    this.idNumber,
    this.dateOfBirth,
    this.note,
    this.userId,
    this.moveInDate,
    this.isPayer = false,
  });

  final String fullName;
  final ResidentRelation relation;
  final String? phone;
  final String? idNumber;
  final DateTime? dateOfBirth;
  final String? note;
  final String? userId;
  final DateTime? moveInDate;
  final bool isPayer;

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Tạo mới: bỏ trường rỗng.
  Map<String, dynamic> toCreateJson({bool includeAccount = true}) => {
    'fullName': fullName.trim(),
    'relation': relation.name,
    if (_clean(phone) != null) 'phone': _clean(phone),
    if (_clean(idNumber) != null) 'idNumber': _clean(idNumber),
    if (dateOfBirth != null) 'dateOfBirth': apiDate(dateOfBirth!),
    if (_clean(note) != null) 'note': _clean(note),
    if (moveInDate != null) 'moveInDate': apiDate(moveInDate!),
    if (includeAccount && userId != null) 'userId': userId,
    if (includeAccount && isPayer) 'isPayer': true,
  };

  /// Cập nhật: trường rỗng gửi null để xóa.
  Map<String, dynamic> toUpdateJson() => {
    'fullName': fullName.trim(),
    'relation': relation.name,
    'phone': _clean(phone),
    'idNumber': _clean(idNumber),
    'dateOfBirth': dateOfBirth == null ? null : apiDate(dateOfBirth!),
    'note': _clean(note),
    'userId': userId,
  };
}
