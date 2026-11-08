import 'package:flutter/material.dart';

/// Sắc thái màu của trạng thái, map sang màu theme (tự đúng cả sáng/tối).
enum StatusTone { neutral, info, warning, success, danger }

/// Nhãn trạng thái nhỏ (phiếu, xe, khách, booking, nhiệm vụ...).
///   StatusChip(label: status.label, tone: status.tone)
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      StatusTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      StatusTone.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
      StatusTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      StatusTone.success => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      StatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
