import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'models.dart';

/// API M2: căn hộ (UC-06, 07) và hồ sơ cư trú (UC-08 đến 12).
class ApartmentsRepository {
  ApartmentsRepository(this._api);
  final ApiClient _api;

  // ------------------------------------------------------------ Căn hộ
  Future<Paged<Apartment>> listApartments({String q = '', ApartmentStatus? status, int page = 1}) =>
      _api.getPaged(
        '/apartments',
        Apartment.fromJson,
        query: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          if (status != null) 'status': status.name,
          'page': page,
          'limit': 30,
        },
      );

  Future<List<Apartment>> myApartments() async {
    final data = await _api.get<List<dynamic>>('/apartments/mine');
    return data.map((e) => Apartment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Apartment> getApartment(String id) async =>
      Apartment.fromJson(await _api.get<Map<String, dynamic>>('/apartments/$id'));

  Future<Apartment> saveApartment({
    String? id,
    required String code,
    required int floor,
    required double area,
    int? bedrooms,
    String? note,
  }) async {
    final body = {
      'code': code.trim(),
      'floor': floor,
      'area': area,
      'bedrooms': ?bedrooms,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    final data = id == null
        ? await _api.post<Map<String, dynamic>>('/apartments', body: body)
        : await _api.patch<Map<String, dynamic>>('/apartments/$id', body: body);
    return Apartment.fromJson(data);
  }

  Future<void> deleteApartment(String id) => _api.delete<dynamic>('/apartments/$id');

  // ------------------------------------------------------------ Cư trú
  Future<List<ResidentRecord>> listResidents(
    String apartmentId,
    List<ResidentStatus> statuses,
  ) async {
    final data = await _api.get<List<dynamic>>(
      '/apartments/$apartmentId/residents',
      query: {'status': statuses.map((s) => s.name).join(',')},
    );
    return data.map((e) => ResidentRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ResidentRecord> createResident(String apartmentId, ResidentInput input) async =>
      ResidentRecord.fromJson(
        await _api.post<Map<String, dynamic>>(
          '/apartments/$apartmentId/residents',
          body: input.toCreateJson(),
        ),
      );

  Future<ResidentRecord> registerMember(String apartmentId, ResidentInput input) async =>
      ResidentRecord.fromJson(
        await _api.post<Map<String, dynamic>>(
          '/apartments/$apartmentId/registrations',
          body: input.toCreateJson(includeAccount: false),
        ),
      );

  Future<Paged<ResidentRecord>> searchResidents({
    String q = '',
    List<ResidentStatus> statuses = const [ResidentStatus.active],
    int page = 1,
  }) => _api.getPaged(
    '/residents',
    ResidentRecord.fromJson,
    query: {
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'status': statuses.map((s) => s.name).join(','),
      'page': page,
      'limit': 30,
    },
  );

  Future<ResidentRecord> getResident(String id) async =>
      ResidentRecord.fromJson(await _api.get<Map<String, dynamic>>('/residents/$id'));

  Future<ResidentRecord> updateResident(String id, ResidentInput input) async =>
      ResidentRecord.fromJson(
        await _api.patch<Map<String, dynamic>>('/residents/$id', body: input.toUpdateJson()),
      );

  Future<void> setPayer(String id) => _api.patch<dynamic>('/residents/$id/payer');

  Future<void> moveOut(String id, {required DateTime date, String? reason}) => _api.patch<dynamic>(
    '/residents/$id/move-out',
    body: {
      'moveOutDate': apiDate(date),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
  );

  // ------------------------------------------------------------ Duyệt
  Future<Paged<ResidentRecord>> listRegistrations({
    ResidentStatus status = ResidentStatus.pending,
    int page = 1,
  }) => _api.getPaged(
    '/residents/registrations',
    ResidentRecord.fromJson,
    query: {'status': status.name, 'page': page, 'limit': 30},
  );

  Future<void> approve(String id) => _api.patch<dynamic>('/residents/$id/approve');

  Future<void> reject(String id, String reason) =>
      _api.patch<dynamic>('/residents/$id/reject', body: {'reason': reason.trim()});
}

final apartmentsRepositoryProvider = Provider<ApartmentsRepository>(
  (ref) => ApartmentsRepository(ref.watch(apiClientProvider)),
);
