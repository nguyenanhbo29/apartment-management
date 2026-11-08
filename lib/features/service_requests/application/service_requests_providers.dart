import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/service_requests_repository.dart';

/// Chi tiết phiếu + timeline + allowedActions. Sau mỗi thao tác: ref.invalidate.
final requestDetailProvider = FutureProvider.autoDispose
    .family<ServiceRequest, String>(
      (ref, id) => ref.watch(serviceRequestsRepositoryProvider).get(id),
    );
