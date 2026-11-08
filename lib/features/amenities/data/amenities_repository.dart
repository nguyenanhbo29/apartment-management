import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'models.dart';

/// M6 — Tiện ích (UC-35, 36) và đặt chỗ (UC-37 → 39).
class AmenitiesRepository {
  AmenitiesRepository(this._api);
  final ApiClient _api;

  Future<List<Amenity>> list({bool includeInactive = false}) async {
    final data = await _api.get<List<dynamic>>(
      '/amenities',
      query: {if (includeInactive) 'includeInactive': 'true'},
    );
    return data
        .map((e) => Amenity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Amenity> get(String id) async =>
      Amenity.fromJson(await _api.get<Map<String, dynamic>>('/amenities/$id'));

  /// Tạo ([id] null) hoặc sửa tiện ích. [data] theo trường của backend.
  Future<Amenity> save(String? id, Map<String, dynamic> data) async =>
      Amenity.fromJson(
        id == null
            ? await _api.post<Map<String, dynamic>>('/amenities', body: data)
            : await _api.patch<Map<String, dynamic>>(
                '/amenities/$id',
                body: data,
              ),
      );

  Future<Amenity> setActive(String id, bool active) async => Amenity.fromJson(
    await _api.patch<Map<String, dynamic>>(
      '/amenities/$id/${active ? 'activate' : 'deactivate'}',
    ),
  );

  Future<List<SlotInfo>> slots(String id, DateTime date) async {
    final data = await _api.get<List<dynamic>>(
      '/amenities/$id/slots',
      query: {'date': apiDate(date)},
    );
    return data
        .map((e) => SlotInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AmenityBooking> book({
    required String amenityId,
    required String apartmentId,
    required DateTime date,
    required String startTime,
    required int people,
    String? note,
  }) async => AmenityBooking.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/amenity-bookings',
      body: {
        'amenityId': amenityId,
        'apartmentId': apartmentId,
        'date': apiDate(date),
        'startTime': startTime,
        'numberOfParticipants': people,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    ),
  );

  Future<Paged<AmenityBooking>> myBookings({
    BookingStatus? status,
    int page = 1,
  }) => _api.getPaged(
    '/amenity-bookings/mine',
    AmenityBooking.fromJson,
    query: {'status': ?status?.name, 'page': page, 'limit': 20},
  );

  /// Hàng chờ Facility / Manager. [status] null = tất cả.
  Future<Paged<AmenityBooking>> queue({
    BookingStatus? status = BookingStatus.pending,
    int page = 1,
  }) => _api.getPaged(
    '/amenity-bookings',
    AmenityBooking.fromJson,
    query: {'status': status?.name ?? 'all', 'page': page, 'limit': 20},
  );

  Future<AmenityBooking> getBooking(String id) async => AmenityBooking.fromJson(
    await _api.get<Map<String, dynamic>>('/amenity-bookings/$id'),
  );

  Future<AmenityBooking> _patch(
    String id,
    String action, [
    Object? body,
  ]) async => AmenityBooking.fromJson(
    await _api.patch<Map<String, dynamic>>(
      '/amenity-bookings/$id/$action',
      body: body,
    ),
  );

  Future<AmenityBooking> approve(String id) => _patch(id, 'approve');
  Future<AmenityBooking> reject(String id, String reason) =>
      _patch(id, 'reject', {'reason': reason});

  /// Ban quản lý hủy khi có sự cố (bắt buộc lý do, không áp dụng hạn hủy).
  Future<AmenityBooking> cancelByStaff(String id, String reason) =>
      _patch(id, 'cancel-by-staff', {'reason': reason});

  Future<AmenityBooking> cancel(String id, {String? reason}) => _patch(
    id,
    'cancel',
    {if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim()},
  );
}

final amenitiesRepositoryProvider = Provider<AmenitiesRepository>(
  (ref) => AmenitiesRepository(ref.watch(apiClientProvider)),
);

final amenityListProvider = FutureProvider.autoDispose
    .family<List<Amenity>, bool>(
      (ref, includeInactive) => ref
          .watch(amenitiesRepositoryProvider)
          .list(includeInactive: includeInactive),
    );

final amenityDetailProvider = FutureProvider.autoDispose
    .family<Amenity, String>(
      (ref, id) => ref.watch(amenitiesRepositoryProvider).get(id),
    );

/// Lưới slot theo (amenityId, ngày yyyy-MM-dd).
final amenitySlotsProvider = FutureProvider.autoDispose
    .family<List<SlotInfo>, (String, String)>(
      (ref, key) => ref
          .watch(amenitiesRepositoryProvider)
          .slots(key.$1, DateTime.parse(key.$2)),
    );

final bookingDetailProvider = FutureProvider.autoDispose
    .family<AmenityBooking, String>(
      (ref, id) => ref.watch(amenitiesRepositoryProvider).getBooking(id),
    );
