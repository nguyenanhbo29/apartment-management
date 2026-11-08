import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';
import 'widgets.dart';

/// UC-29: Phiếu của tôi (Resident) — phiếu mình tạo + phiếu sửa chữa của căn mình ở.
class MyRequestsPage extends ConsumerStatefulWidget {
  const MyRequestsPage({super.key});

  @override
  ConsumerState<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends ConsumerState<MyRequestsPage> {
  RequestStatus? _status;
  int _reload = 0;

  Future<void> _openCreate() async {
    final created = await context.push<bool>('/requests/new');
    if (created == true) setState(() => _reload++);
  }

  Future<void> _openDetail(ServiceRequest r) async {
    await context.push('/requests/${r.id}');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(serviceRequestsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Phiếu của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Tạo phiếu'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in <RequestStatus?>[null, ...RequestStatus.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s?.label ?? 'Tất cả'),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<ServiceRequest>(
              key: ValueKey('${_status?.api}|$_reload'),
              fetch: (page) => repo.listMine(status: _status, page: page),
              emptyText: 'Chưa có phiếu nào',
              itemBuilder: (context, r) =>
                  RequestTile(request: r, onTap: () => _openDetail(r)),
            ),
          ),
        ],
      ),
    );
  }
}
