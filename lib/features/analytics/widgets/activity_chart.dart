import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../care_analytics.dart';

/// Daily activity bar chart.
///
/// Renders the same [DailyMetric] series that [CareAnalytics] feeds to the AI,
/// so what the owner sees and what the assistant describes are guaranteed to be
/// the same numbers.
class ActivityChart extends StatelessWidget {
  const ActivityChart({
    super.key,
    required this.series,
    this.color = AppColors.exercise,
    this.showAverageLine = true,
  });

  final List<DailyMetric> series;
  final Color color;
  final bool showAverageLine;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return Center(
        child: Text(
          'No activity data yet',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final double maxValue =
        series.map((DailyMetric d) => d.value).fold<double>(0, (a, b) => a > b ? a : b);

    // A flat zero series would collapse the axis; give it a nominal ceiling so
    // the empty state still renders a readable grid.
    final double maxY = maxValue <= 0 ? 30 : maxValue * 1.25;

    final double average = series.isEmpty
        ? 0
        : series.map((DailyMetric d) => d.value).reduce((a, b) => a + b) /
            series.length;

    final Color gridColor = Theme.of(context).colorScheme.outlineVariant;
    final Color labelColor = AppColors.inkFaint;

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (double value) => FlLine(
            color: gridColor,
            strokeWidth: 1,
            dashArray: <int>[4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: maxY / 3,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value.round().toString(),
                    style: TextStyle(fontSize: 10, color: labelColor),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int i = value.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                final bool isToday = i == series.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    series[i].shortWeekday,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color: isToday ? color : labelColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (
              BarChartGroupData group,
              int groupIndex,
              BarChartRodData rod,
              int rodIndex,
            ) {
              final DailyMetric d = series[group.x];
              return BarTooltipItem(
                '${d.weekdayLabel}\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                children: <TextSpan>[
                  TextSpan(
                    text: '${rod.toY.round()} min',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        extraLinesData: showAverageLine && average > 0
            ? ExtraLinesData(
                horizontalLines: <HorizontalLine>[
                  HorizontalLine(
                    y: average,
                    color: color.withValues(alpha: 0.55),
                    strokeWidth: 1.5,
                    dashArray: <int>[6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                      labelResolver: (_) => 'avg ${average.round()}',
                    ),
                  ),
                ],
              )
            : const ExtraLinesData(),
        barGroups: List<BarChartGroupData>.generate(series.length, (int i) {
          final DailyMetric d = series[i];
          final bool isToday = i == series.length - 1;
          return BarChartGroupData(
            x: i,
            barRods: <BarChartRodData>[
              BarChartRodData(
                toY: d.value,
                width: series.length > 10 ? 10 : 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                color: d.value <= 0
                    ? gridColor
                    : (isToday ? color : color.withValues(alpha: 0.55)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: gridColor.withValues(alpha: 0.30),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
