import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

/// "—" cho chỉ số chưa có dữ liệu (backend trả null), không hiển thị 0.
String dash(num? v, [String Function(num v)? fmt]) =>
    v == null ? '—' : (fmt?.call(v) ?? '$v');

String percent(num? v) => dash(v, (x) => '${(x * 100).round()}%');

// ======================================================================== Khoảng thời gian
enum RangePreset {
  last7('7 ngày'),
  last30('30 ngày'),
  thisMonth('Tháng này'),
  custom('Tùy chọn');

  const RangePreset(this.label);
  final String label;

  DateTimeRange? resolve(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      last7 => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      last30 => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
      thisMonth => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: today,
      ),
      custom => null,
    };
  }
}

/// Bộ chọn khoảng thời gian một hàng, đặt trên cùng (áp cho mọi số liệu bên dưới).
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.preset,
    required this.range,
    required this.onChanged,
  });

  final RangePreset preset;
  final DateTimeRange range;
  final void Function(RangePreset preset, DateTimeRange range) onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
      initialDateRange: range,
    );
    if (picked != null) onChanged(RangePreset.custom, picked);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final p in RangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  p == RangePreset.custom && preset == RangePreset.custom
                      ? '${formatDate(range.start)} – ${formatDate(range.end)}'
                      : p.label,
                ),
                selected: preset == p,
                onSelected: (_) {
                  final r = p.resolve(DateTime.now());
                  r == null ? _pick(context) : onChanged(p, r);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ======================================================================== Thẻ số
/// Một chỉ số lớn. [alert] = đang có vấn đề (quá hạn...): màu cảnh báo + biểu tượng, không chỉ màu.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.alert = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: alert ? scheme.errorContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    alert ? Icons.warning_amber_rounded : icon,
                    size: 20,
                    color: alert ? scheme.onErrorContainer : scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: alert
                            ? scheme.onErrorContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: alert ? scheme.onErrorContainer : scheme.onSurface,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: alert
                        ? scheme.onErrorContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================== Biểu đồ cột
class BarDatum {
  const BarDatum({
    required this.label,
    required this.shortLabel,
    required this.value,
  });
  final String label;
  final String shortLabel;
  final int value;
}

/// Cột đứng một chuỗi số liệu (một màu = màu chính của theme, tự đúng sáng/tối).
/// Cột mảnh, bo 4px ở đầu dữ liệu, lưới ngang mờ, chạm để xem tooltip, [onTap] để mở danh sách nguồn.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.data,
    this.onTap,
    this.height = 200,
  });

  final List<BarDatum> data;
  final void Function(int index)? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxValue = data.fold<int>(0, (m, d) => math.max(m, d.value));
    final interval = math.max(1, (maxValue / 4).ceil()).toDouble();
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: math.max(interval * 4, maxValue.toDouble()),
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: interval,
                getTitlesWidget: (value, meta) => value % 1 == 0
                    ? Text(value.toInt().toString(), style: labelStyle)
                    : const SizedBox.shrink(),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data[i].shortLabel,
                      style: labelStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    '${data[group.x].label}\n${data[group.x].value}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
            touchCallback: (event, response) {
              final spot = response?.spot;
              if (onTap != null && event is FlTapUpEvent && spot != null) {
                onTap!(spot.touchedBarGroupIndex);
              }
            },
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].value.toDouble(),
                    width: 16,
                    color: scheme.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Danh sách thanh ngang (nhãn dài như tên tiện ích): nhãn trái, giá trị phải, thanh tỷ lệ.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items, this.onTap});

  final List<(String label, int value)> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxValue = items.fold<int>(0, (m, e) => math.max(m, e.$2));
    return Column(
      children: [
        for (final (label, value) in items)
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                      Text(
                        '$value',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxValue == 0 ? 0 : value / maxValue,
                      minHeight: 8,
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
