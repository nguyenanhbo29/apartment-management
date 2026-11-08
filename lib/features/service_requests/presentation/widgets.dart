import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/models.dart';

// Ảnh, chọn ảnh, hộp thoại lý do: dùng chung ở core (M3, M5...)
export '../../../core/widgets/media_widgets.dart';

class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: status.label, tone: status.tone);
}

const overdueChip = StatusChip(
  label: 'Quá hạn',
  tone: StatusTone.danger,
  icon: Icons.schedule,
);

/// Một dòng phiếu trong danh sách.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.onTap,
    this.showAssignee = false,
  });

  final ServiceRequest request;
  final VoidCallback? onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final theme = Theme.of(context);
    final meta = [
      r.code,
      if (r.apartmentCode != null) 'Căn ${r.apartmentCode}',
      r.category.label,
      if (showAssignee && r.assignedStaffName != null) r.assignedStaffName!,
    ].join(' · ');
    final time = r.deadline != null && r.status != RequestStatus.closed
        ? 'Hạn ${formatDateTime(r.deadline)}'
        : formatDateTime(r.createdAt);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          r.type == RequestType.repair
              ? Icons.build_outlined
              : Icons.report_outlined,
          size: 20,
        ),
      ),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RequestStatusChip(r.status),
                if (r.isOverdue) overdueChip,
                if (r.priority.index >= RequestPriority.high.index)
                  StatusChip(label: r.priority.label, tone: r.priority.tone),
                Text(time, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
