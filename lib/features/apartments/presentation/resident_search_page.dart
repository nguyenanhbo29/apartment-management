import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';
import 'widgets.dart';

/// UC-08: Tra cứu hồ sơ cư dân toàn tòa (Quản lý, Kế toán, Lễ tân).
class ResidentSearchPage extends ConsumerStatefulWidget {
  const ResidentSearchPage({super.key});

  @override
  ConsumerState<ResidentSearchPage> createState() => _ResidentSearchPageState();
}

class _ResidentSearchPageState extends ConsumerState<ResidentSearchPage> {
  Timer? _debounce;
  String _q = '';
  bool _includeEnded = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(apartmentsRepositoryProvider);
    final statuses = [ResidentStatus.active, if (_includeEnded) ResidentStatus.ended];

    return Scaffold(
      appBar: AppBar(title: const Text('Cư dân')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _q = q));
              },
              decoration: const InputDecoration(
                hintText: 'Tên, SĐT, CCCD hoặc mã căn hộ',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Gồm cả người đã chuyển đi'),
                selected: _includeEnded,
                onSelected: (v) => setState(() => _includeEnded = v),
              ),
            ),
          ),
          Expanded(
            child: PagedListView<ResidentRecord>(
              key: ValueKey('$_q|$_includeEnded'),
              fetch: (page) => repo.searchResidents(q: _q, statuses: statuses, page: page),
              emptyText: 'Không tìm thấy cư dân',
              itemBuilder: (context, r) => ResidentTile(
                record: r,
                showApartment: true,
                onTap: () => context.push('/apartments/${r.apartmentId}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
