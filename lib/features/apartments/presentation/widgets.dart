import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../data/models.dart';

/// Nhãn trạng thái nhỏ có màu.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }

  factory StatusBadge.apartment(BuildContext context, ApartmentStatus s) {
    final scheme = Theme.of(context).colorScheme;
    return StatusBadge(
      s.label,
      color: s == ApartmentStatus.occupied ? scheme.primary : scheme.outline,
    );
  }

  factory StatusBadge.resident(BuildContext context, ResidentStatus s) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (s) {
      ResidentStatus.active => scheme.primary,
      ResidentStatus.pending => scheme.tertiary,
      ResidentStatus.rejected => scheme.error,
      ResidentStatus.ended => scheme.outline,
    };
    return StatusBadge(s.label, color: color);
  }
}

/// Một dòng hồ sơ cư trú.
class ResidentTile extends StatelessWidget {
  const ResidentTile({
    super.key,
    required this.record,
    this.showApartment = false,
    this.onTap,
    this.trailing,
  });

  final ResidentRecord record;
  final bool showApartment;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final theme = Theme.of(context);
    final lines = <String>[
      [
        if (showApartment && r.apartmentCode != null) 'Căn ${r.apartmentCode}',
        r.relation.label,
        if (r.phone != null) r.phone!,
      ].join(' · '),
      if (r.status == ResidentStatus.active && r.moveInDate != null)
        'Chuyển đến ${formatDate(r.moveInDate)}',
      if (r.status == ResidentStatus.ended)
        'Chuyển đi ${formatDate(r.moveOutDate)}'
            '${r.moveOutReason != null ? ' · ${r.moveOutReason}' : ''}',
      if (r.status == ResidentStatus.pending) 'Gửi lúc ${formatDateTime(r.createdAt)}',
      if (r.status == ResidentStatus.rejected && r.rejectReason != null) 'Lý do: ${r.rejectReason}',
    ];

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(
          r.relation == ResidentRelation.owner ? Icons.home_outlined : Icons.person_outline,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(r.fullName, overflow: TextOverflow.ellipsis)),
          if (r.isPayer) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Người nộp phí',
              child: Icon(Icons.payments_outlined, size: 18, color: theme.colorScheme.primary),
            ),
          ],
          if (r.hasAccount) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Có tài khoản ứng dụng',
              child: Icon(Icons.phone_android, size: 16, color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing:
          trailing ??
          (r.status == ResidentStatus.active ? null : StatusBadge.resident(context, r.status)),
    );
  }
}

/// Chọn ngày bằng date picker, hiển thị như một ô nhập.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.clearable = true,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? (lastDate != null && lastDate!.isBefore(now) ? lastDate! : now),
          firstDate: firstDate ?? DateTime(1900),
          lastDate: lastDate ?? DateTime(now.year + 5),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: clearable && value != null
              ? IconButton(
                  tooltip: 'Xóa',
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(value == null ? '' : formatDate(value)),
      ),
    );
  }
}
