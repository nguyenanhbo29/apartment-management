import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';
import 'widgets.dart';

/// UC-31: Việc của tôi (Staff): đang làm / quá hạn / đã xong.
/// M7 sẽ trộn thêm nhiệm vụ vận hành vào cùng danh sách.
class MyAssignmentsPage extends ConsumerStatefulWidget {
  const MyAssignmentsPage({super.key});

  @override
  ConsumerState<MyAssignmentsPage> createState() => _MyAssignmentsPageState();
}

class _MyAssignmentsPageState extends ConsumerState<MyAssignmentsPage> {
  int _reload = 0;

  Future<void> _openDetail(ServiceRequest r) async {
    await context.push('/requests/${r.id}');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(serviceRequestsRepositoryProvider);
    return DefaultTabController(
      length: AssignmentTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Việc của tôi'),
          bottom: TabBar(
            tabs: [for (final t in AssignmentTab.values) Tab(text: t.label)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in AssignmentTab.values)
              PagedListView<ServiceRequest>(
                key: ValueKey('${t.name}|$_reload'),
                fetch: (page) => repo.assignments(tab: t, page: page),
                emptyText: t == AssignmentTab.overdue
                    ? 'Không có việc quá hạn'
                    : 'Không có việc',
                itemBuilder: (context, r) =>
                    RequestTile(request: r, onTap: () => _openDetail(r)),
              ),
          ],
        ),
      ),
    );
  }
}
