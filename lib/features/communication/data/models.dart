import '../../../core/utils/formatters.dart';
import '../../auth/data/app_user.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.linkKind,
    this.linkId,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? linkKind;
  final String? linkId;
  final DateTime? createdAt;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    isRead: isRead ?? this.isRead,
    linkKind: linkKind,
    linkId: linkId,
    createdAt: createdAt,
  );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final link = j['link'] as Map?;
    return AppNotification(
      id: j['_id'].toString(),
      type: (j['type'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      isRead: j['isRead'] == true,
      linkKind: link?['kind'] as String?,
      linkId: link?['id']?.toString(),
      createdAt: parseDate(j['createdAt']),
    );
  }
}

enum AudienceType {
  all('Tất cả'),
  roles('Theo vai trò'),
  floors('Theo tầng'),
  apartments('Theo căn hộ');

  const AudienceType(this.label);
  final String label;

  static AudienceType parse(String? v) =>
      AudienceType.values.firstWhere((e) => e.name == v, orElse: () => AudienceType.all);
}

class Audience {
  const Audience({
    required this.type,
    this.roles = const [],
    this.floors = const [],
    this.apartmentIds = const [],
  });

  final AudienceType type;
  final List<UserRole> roles;
  final List<int> floors;
  final List<String> apartmentIds;

  String get label => switch (type) {
    AudienceType.all => 'Tất cả',
    AudienceType.roles => roles.map((r) => r.label).join(', '),
    AudienceType.floors => 'Tầng ${floors.join(', ')}',
    AudienceType.apartments => '${apartmentIds.length} căn hộ',
  };

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (type == AudienceType.roles) 'roles': roles.map((r) => r.name).toList(),
    if (type == AudienceType.floors) 'floors': floors,
    if (type == AudienceType.apartments) 'apartmentIds': apartmentIds,
  };

  factory Audience.fromJson(Map<String, dynamic> j) => Audience(
    type: AudienceType.parse(j['type'] as String?),
    roles: ((j['roles'] as List?) ?? const []).map((e) => UserRole.parse(e as String)).toList(),
    floors: ((j['floors'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
    apartmentIds: ((j['apartmentIds'] as List?) ?? const []).map((e) => e.toString()).toList(),
  );
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.audience,
    required this.isPinned,
    required this.removed,
    this.expiresAt,
    this.publishedAt,
    this.recipientCount = 0,
    this.createdByName,
  });

  final String id;
  final String title;
  final String content;
  final Audience audience;
  final bool isPinned;
  final bool removed;
  final DateTime? expiresAt;
  final DateTime? publishedAt;
  final int recipientCount;
  final String? createdByName;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get active => !removed && !expired;

  factory Announcement.fromJson(Map<String, dynamic> j) {
    final by = j['createdBy'];
    return Announcement(
      id: j['_id'].toString(),
      title: j['title'] as String,
      content: j['content'] as String,
      audience: Audience.fromJson((j['audience'] as Map).cast<String, dynamic>()),
      isPinned: j['isPinned'] == true,
      removed: j['status'] == 'removed',
      expiresAt: parseDate(j['expiresAt']),
      publishedAt: parseDate(j['publishedAt']),
      recipientCount: (j['recipientCount'] as num?)?.toInt() ?? 0,
      createdByName: by is Map ? by['fullName'] as String? : null,
    );
  }
}
