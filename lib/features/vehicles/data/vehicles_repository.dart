import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import 'models.dart';

/// M3 — Xe (UC-13, 14, 15).
class VehiclesRepository {
  VehiclesRepository(this._api);
  final ApiClient _api;

  static const _base = '/vehicles';

  Future<Vehicle> register({
    required String apartmentId,
    required VehicleType type,
    required String plateNumber,
    String? brand,
    String? color,
    UploadFile? image,
  }) async => Vehicle.fromJson(
    await _api.multipart<Map<String, dynamic>>(
      'POST',
      _base,
      fields: {
        'apartmentId': apartmentId,
        'type': type.name,
        'plateNumber': plateNumber,
        if ((brand ?? '').trim().isNotEmpty) 'brand': brand!.trim(),
        if ((color ?? '').trim().isNotEmpty) 'color': color!.trim(),
      },
      files: [?image],
    ),
  );

  Future<Paged<Vehicle>> listMine({VehicleStatus? status, int page = 1}) =>
      _api.getPaged(
        '$_base/mine',
        Vehicle.fromJson,
        query: {'status': ?status?.name, 'page': page, 'limit': 20},
      );

  Future<Paged<Vehicle>> list({
    VehicleStatus? status,
    String plate = '',
    int page = 1,
  }) => _api.getPaged(
    _base,
    Vehicle.fromJson,
    query: {
      'status': ?status?.name,
      if (plate.trim().isNotEmpty) 'plate': plate.trim(),
      'page': page,
      'limit': 20,
    },
  );

  Future<Vehicle> get(String id) async =>
      Vehicle.fromJson(await _api.get<Map<String, dynamic>>('$_base/$id'));

  Future<Vehicle> approve(String id) async => Vehicle.fromJson(
    await _api.patch<Map<String, dynamic>>('$_base/$id/approve'),
  );

  Future<Vehicle> reject(String id, String reason) async => Vehicle.fromJson(
    await _api.patch<Map<String, dynamic>>(
      '$_base/$id/reject',
      body: {'reason': reason},
    ),
  );

  Future<Vehicle> deactivate(String id) async => Vehicle.fromJson(
    await _api.patch<Map<String, dynamic>>('$_base/$id/deactivate'),
  );
}

final vehiclesRepositoryProvider = Provider<VehiclesRepository>(
  (ref) => VehiclesRepository(ref.watch(apiClientProvider)),
);

final vehicleDetailProvider = FutureProvider.autoDispose
    .family<Vehicle, String>(
      (ref, id) => ref.watch(vehiclesRepositoryProvider).get(id),
    );
