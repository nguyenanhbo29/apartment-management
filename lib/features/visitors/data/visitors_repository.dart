import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'models.dart';

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// M3 — Khách (UC-16, 17, 18). Ngày + giờ gửi theo giờ Việt Nam (backend tự đổi sang UTC).
class VisitorsRepository {
  VisitorsRepository(this._api);
  final ApiClient _api;

  static const _base = '/visitors';

  Future<Visitor> create({
    required String apartmentId,
    required String visitorName,
    String? visitorPhone,
    required int numberOfPeople,
    required DateTime visitDate,
    required TimeOfDay timeFrom,
    required TimeOfDay timeTo,
    String? vehiclePlate,
    String? note,
  }) async => Visitor.fromJson(
    await _api.post<Map<String, dynamic>>(
      _base,
      body: {
        'apartmentId': apartmentId,
        'visitorName': visitorName.trim(),
        if ((visitorPhone ?? '').trim().isNotEmpty)
          'visitorPhone': visitorPhone!.trim(),
        'numberOfPeople': numberOfPeople,
        'visitDate': apiDate(visitDate),
        'timeFrom': _hhmm(timeFrom),
        'timeTo': _hhmm(timeTo),
        if ((vehiclePlate ?? '').trim().isNotEmpty)
          'vehiclePlate': vehiclePlate!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    ),
  );

  Future<Paged<Visitor>> listMine({VisitorStatus? status, int page = 1}) =>
      _api.getPaged(
        '$_base/mine',
        Visitor.fromJson,
        query: {'status': ?status?.api, 'page': page, 'limit': 20},
      );

  /// Danh sách tại cổng: mặc định hôm nay; có [code] thì bỏ qua ngày.
  Future<Paged<Visitor>> gate({
    DateTime? date,
    String? code,
    String? phone,
    VisitorStatus? status,
    int page = 1,
  }) => _api.getPaged(
    _base,
    Visitor.fromJson,
    query: {
      if (date != null) 'date': apiDate(date),
      'code': ?code,
      'phone': ?phone,
      'status': ?status?.api,
      'page': page,
      'limit': 50,
    },
  );

  Future<Visitor> get(String id) async =>
      Visitor.fromJson(await _api.get<Map<String, dynamic>>('$_base/$id'));

  Future<Visitor> _patch(String id, String action, [Object? body]) async =>
      Visitor.fromJson(
        await _api.patch<Map<String, dynamic>>(
          '$_base/$id/$action',
          body: body,
        ),
      );

  Future<Visitor> cancel(String id, {String? reason}) => _patch(
    id,
    VisitorAction.cancel,
    {if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim()},
  );

  Future<Visitor> checkIn(String id) => _patch(id, VisitorAction.checkIn);
  Future<Visitor> checkOut(String id) => _patch(id, VisitorAction.checkOut);
}

final visitorsRepositoryProvider = Provider<VisitorsRepository>(
  (ref) => VisitorsRepository(ref.watch(apiClientProvider)),
);

final visitorDetailProvider = FutureProvider.autoDispose
    .family<Visitor, String>(
      (ref, id) => ref.watch(visitorsRepositoryProvider).get(id),
    );
