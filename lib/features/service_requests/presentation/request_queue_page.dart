import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../data/models.dart';
import '../data/service_requests_repository.dart';
import 'widgets.dart';

/// UC-30: Hàng chờ phiếu (Manager). Mặc định phiếu mới, ưu tiên cao lên trước.
class RequestQueuePage extends ConsumerStatefulWidget {
  const RequestQueuePage({super.key, this.initial = const QueueFilter()});

  /// Bộ lọc ban đầu (dashboard mở sẵn "quá hạn" hoặc một trạng thái).
  final QueueFilter initial;

  /// Từ query của route: ?filter=overdue | ?status=in_progress | ?status=all
  factory RequestQueuePage.fromQuery(Map<String, String> q) => RequestQueuePage(
    initial: switch ((q['filter'], q['status'])) {
      ('overdue', _) => const QueueFilter(overdue: true),
      (_, 'all') => const QueueFilter(status: null),
      (_, final String s) => QueueFilter(status: RequestStatus.parse(s)),
      _ => const QueueFilter(),
    },
  );

  @override
  ConsumerState<RequestQueuePage> createState() => _RequestQueuePageState();
}

class _RequestQueuePageState extends ConsumerState<RequestQueuePage> {
  late QueueFilter _filter = widget.initial;
  int _reload = 0;

  static final _options = <(String, QueueFilter)>[
    ('Chờ tiếp nhận', const QueueFilter()),
    ('Quá hạn', const QueueFilter(overdue: true)),
    for (final s in [
      RequestStatus.assigned,
      RequestStatus.inProgress,
      RequestStatus.waitingConfirmation,
      RequestStatus.reopened,
      RequestStatus.closed,
      RequestStatus.rejected,
    ])
      (s.label, QueueFilter(status: s)),
    ('Tất cả', const QueueFilter(status: null)),
  ];

  bool _same(QueueFilter a, QueueFilter b) =>
      a.status == b.status && a.overdue == b.overdue;

  Future<void> _openDetail(ServiceRequest r) async {
    await context.push('/requests/${r.id}');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(serviceRequestsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Phiếu yêu cầu')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (label, f) in _options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _same(_filter, f),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<ServiceRequest>(
              key: ValueKey(
                '${_filter.status?.api}|${_filter.overdue}|$_reload',
              ),
              fetch: (page) => repo.queue(filter: _filter, page: page),
              emptyText: 'Không có phiếu',
              itemBuilder: (context, r) => RequestTile(
                request: r,
                showAssignee: true,
                onTap: () => _openDetail(r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
