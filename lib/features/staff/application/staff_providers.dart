import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/staff_repository.dart';

/// Số nhân viên theo bộ phận (nhãn tab). Làm mới bằng ref.invalidate.
final departmentSummariesProvider =
    FutureProvider.autoDispose<List<DepartmentSummary>>(
      (ref) => ref.watch(staffRepositoryProvider).departments(),
    );
