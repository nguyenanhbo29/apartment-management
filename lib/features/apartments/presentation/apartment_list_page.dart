import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../auth/application/auth_controller.dart';
import '../data/apartments_repository.dart';
import '../data/models.dart';
import 'widgets.dart';

/// UC-06: Danh sách căn hộ (Quản lý, Kế toán, Lễ tân). Chỉ Quản lý được thêm.
class ApartmentListPage extends ConsumerStatefulWidget {
  const ApartmentListPage({super.key});

  @override
  ConsumerState<ApartmentListPage> createState() => _ApartmentListPageState();
}

class _ApartmentListPageState extends ConsumerState<ApartmentListPage> {
  Timer? _debounce;
  String _q = '';
  ApartmentStatus? _status;
  int _reload = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _q = q));
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final isManager = ref.watch(currentUserProvider)?.isManager ?? false;
    final repo = ref.watch(apartmentsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Căn hộ')),
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _open('/apartments/new'),
              icon: const Icon(Icons.add_home_outlined),
              label: const Text('Thêm căn hộ'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Tìm theo mã căn hộ',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final s in ApartmentStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (sel) => setState(() => _status = sel ? s : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<Apartment>(
              key: ValueKey('$_q|$_status|$_reload'),
              fetch: (page) => repo.listApartments(q: _q, status: _status, page: page),
              emptyText: 'Chưa có căn hộ nào',
              itemBuilder: (context, a) => ListTile(
                onTap: () => _open('/apartments/${a.id}'),
                leading: CircleAvatar(child: Text('${a.floor}')),
                title: Text('Căn ${a.code}'),
                subtitle: Text(
                  [
                    formatArea(a.area),
                    if (a.ownerName != null) 'Chủ hộ: ${a.ownerName}',
                    if (a.residentCount > 0) '${a.residentCount} người',
                  ].join(' · '),
                ),
                trailing: StatusBadge.apartment(context, a.status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
