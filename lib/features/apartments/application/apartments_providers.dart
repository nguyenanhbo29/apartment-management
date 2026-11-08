import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/apartments_repository.dart';
import '../data/models.dart';

final apartmentDetailProvider = FutureProvider.autoDispose.family<Apartment, String>(
  (ref, id) => ref.watch(apartmentsRepositoryProvider).getApartment(id),
);

/// Key: (apartmentId, danh sách trạng thái)
typedef ResidentsQuery = (String apartmentId, String statusesCsv);

final apartmentResidentsProvider = FutureProvider.autoDispose
    .family<List<ResidentRecord>, ResidentsQuery>((ref, q) {
      final statuses = q.$2.split(',').map(ResidentStatus.parse).toList();
      return ref.watch(apartmentsRepositoryProvider).listResidents(q.$1, statuses);
    });

ResidentsQuery residentsQuery(String apartmentId, List<ResidentStatus> statuses) =>
    (apartmentId, statuses.map((s) => s.name).join(','));

final myApartmentsProvider = FutureProvider.autoDispose<List<Apartment>>(
  (ref) => ref.watch(apartmentsRepositoryProvider).myApartments(),
);

final residentDetailProvider = FutureProvider.autoDispose.family<ResidentRecord, String>(
  (ref, id) => ref.watch(apartmentsRepositoryProvider).getResident(id),
);

/// Làm mới mọi dữ liệu liên quan căn hộ sau khi thay đổi.
void invalidateApartmentData(WidgetRef ref) {
  ref.invalidate(apartmentDetailProvider);
  ref.invalidate(apartmentResidentsProvider);
  ref.invalidate(myApartmentsProvider);
  ref.invalidate(residentDetailProvider);
}
