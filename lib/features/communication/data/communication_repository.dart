import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'models.dart';

/// API M8: bảng tin (UC-43, 44) và thông báo (UC-45, 46).
class CommunicationRepository {
  CommunicationRepository(this._api);
  final ApiClient _api;

  // ------------------------------------------------------------ Thông báo
  Future<Paged<AppNotification>> listNotifications({int page = 1, bool unreadOnly = false}) =>
      _api.getPaged(
        '/notifications',
        AppNotification.fromJson,
        query: {'page': page, 'limit': 30, if (unreadOnly) 'unreadOnly': 'true'},
      );

  Future<int> unreadCount() async {
    final data = await _api.get<Map<String, dynamic>>('/notifications/unread-count');
    return (data['count'] as num).toInt();
  }

  Future<void> markRead(String id) => _api.patch<dynamic>('/notifications/$id/read');

  Future<void> markAllRead() => _api.patch<dynamic>('/notifications/read-all');

  // ------------------------------------------------------------ Bảng tin
  Future<Paged<Announcement>> listAnnouncements({int page = 1, bool includeInactive = false}) =>
      _api.getPaged(
        '/announcements',
        Announcement.fromJson,
        query: {'page': page, 'limit': 20, if (includeInactive) 'includeInactive': 'true'},
      );

  Future<Announcement> getAnnouncement(String id) async =>
      Announcement.fromJson(await _api.get<Map<String, dynamic>>('/announcements/$id'));

  Future<Announcement> createAnnouncement({
    required String title,
    required String content,
    required Audience audience,
    bool isPinned = false,
    DateTime? expiresAt,
  }) async => Announcement.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/announcements',
      body: {
        'title': title.trim(),
        'content': content.trim(),
        'audience': audience.toJson(),
        'isPinned': isPinned,
        // Hết hạn cuối ngày đã chọn
        if (expiresAt != null) 'expiresAt': '${apiDate(expiresAt)}T23:59:59',
      },
    ),
  );

  Future<void> setPinned(String id, bool isPinned) =>
      _api.patch<dynamic>('/announcements/$id/pin', body: {'isPinned': isPinned});

  Future<void> remove(String id) => _api.patch<dynamic>('/announcements/$id/remove');
}

final communicationRepositoryProvider = Provider<CommunicationRepository>(
  (ref) => CommunicationRepository(ref.watch(apiClientProvider)),
);
