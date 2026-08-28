import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../care/care_controller.dart';
import '../care_analytics.dart';
import '../widgets/activity_chart.dart';

/// Care analytics for the selected pet.
///
/// Everything here is computed by [CareAnalytics] from the pet's own records —
/// no model is involved, so the figures are deterministic and reproducible.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final TrendResult? trend = care.trend;
    final CompletionStat? feeding = care.feedingStat;
    final CompletionStat? meds = care.medicationStat;

    if (care.loading || trend == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const LoadingView(message: 'Calculating…'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${care.pet.name}\'s analytics')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          children: <Widget>[
            // ------------------------------------------------ headline stats
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Feeding',
                    value: feeding != null && feeding.hasData
                        ? '${feeding.percent.round()}%'
                        : '—',
                    caption: feeding?.label,
                    icon: CareType.feeding.icon,
                    color: AppColors.feeding,
                    progress: feeding != null && feeding.hasData
                        ? feeding.percent / 100
                        : null,
                  ),
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: StatTile(
                    label: 'Medication',
                    value: meds != null && meds.hasData
                        ? '${meds.percent.round()}%'
                        : '—',
                    caption: meds?.label ?? 'None scheduled',
                    icon: CareType.medicine.icon,
                    color: AppColors.medicine,
                    progress:
                        meds != null && meds.hasData ? meds.percent / 100 : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.gapMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Daily activity',
                    value: trend.hasData ? '${trend.mean.round()} min' : '—',
                    caption: '14-day average',
                    icon: CareType.exercise.icon,
                    color: AppColors.exercise,
                  ),
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: StatTile(
                    label: 'Active days',
                    value: trend.hasData
                        ? '${trend.series.where((DailyMetric d) => d.value > 0).length}/${trend.series.length}'
                        : '—',
                    caption: 'Days with exercise',
                    icon: Icons.event_available_rounded,
                    color: AppColors.leaf,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.gapXl),

            // ------------------------------------------------ activity trend
            SectionHeader(
              title: 'Activity trend',
              subtitle: 'Minutes recorded per day, last 14 days',
              icon: Icons.show_chart_rounded,
            ),
            AppCard(
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 190,
                    child: ActivityChart(
                      series: trend.series,
                      color: AppColors.exercise,
                    ),
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.gapMd),
                    decoration: BoxDecoration(
                      color: _trendColor(trend.direction).withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _trendIcon(trend.direction),
                          size: 19,
                          color: _trendColor(trend.direction),
                        ),
                        const SizedBox(width: AppTheme.gapMd),
                        Expanded(
                          child: Text(
                            trend.describe(care.pet.name),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // --------------------------------------------------- breakdowns
            SectionHeader(
              title: 'Care breakdown',
              subtitle: 'Last 7 days',
              icon: Icons.donut_small_rounded,
            ),
            AppCard(
              child: Column(
                children: <Widget>[
                  _MetricBar(
                    label: 'Feeding completed',
                    stat: feeding,
                    color: AppColors.feeding,
                    icon: CareType.feeding.icon,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _MetricBar(
                    label: 'Medication given',
                    stat: meds,
                    color: AppColors.medicine,
                    icon: CareType.medicine.icon,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _CountRow(
                    label: 'Exercise sessions',
                    value: care.exercise.length.toString(),
                    caption: 'in the last 14 days',
                    color: AppColors.exercise,
                    icon: CareType.exercise.icon,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _CountRow(
                    label: 'Grooming tasks',
                    value: care.grooming.length.toString(),
                    caption: care.grooming.where((g) => g.isOverdue).isEmpty
                        ? 'all on schedule'
                        : '${care.grooming.where((g) => g.isOverdue).length} overdue',
                    color: AppColors.grooming,
                    icon: CareType.grooming.icon,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _CountRow(
                    label: 'Vaccinations',
                    value: care.vaccinations.length.toString(),
                    caption: care.today?.nextVaccination == null
                        ? 'none upcoming'
                        : care.today!.nextVaccination!.dueLabel.toLowerCase(),
                    color: AppColors.vaccination,
                    icon: CareType.vaccination.icon,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  _CountRow(
                    label: 'Vet appointments',
                    value: care.appointments.length.toString(),
                    caption: care.today?.nextAppointment == null
                        ? 'none upcoming'
                        : care.today!.nextAppointment!.whenLabel.toLowerCase(),
                    color: AppColors.vet,
                    icon: CareType.appointment.icon,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // ---------------------------------------------------- anomalies
            if (care.anomalies.isNotEmpty) ...<Widget>[
              SectionHeader(
                title: 'Detected patterns',
                subtitle: 'Observations about the recorded data',
                icon: Icons.insights_rounded,
              ),
              ...care.anomalies.map((CareAnomaly a) => Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                    child: AppCard(
                      accent: a.severity == AnomalySeverity.watch
                          ? AppColors.warning
                          : AppColors.info,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              CareIconTile(
                                icon: a.type.icon,
                                color: a.type.color,
                                size: 36,
                              ),
                              const SizedBox(width: AppTheme.gapMd),
                              Expanded(
                                child: Text(
                                  a.title,
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              AppPill(
                                label: a.severity.label,
                                color: a.severity == AnomalySeverity.watch
                                    ? AppColors.warning
                                    : AppColors.info,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.gapSm),
                          Text(
                            a.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppTheme.gapSm),
                          Row(
                            children: <Widget>[
                              Text(
                                'Signal strength',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(width: AppTheme.gapSm),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: a.confidence,
                                    minHeight: 4,
                                    backgroundColor: AppColors.line,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      a.severity == AnomalySeverity.watch
                                          ? AppColors.warning
                                          : AppColors.info,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTheme.gapSm),
                              Text(
                                '${(a.confidence * 100).round()}%',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
            ] else
              AppCard(
                child: EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  accent: AppColors.success,
                  compact: true,
                  title: 'No unusual patterns',
                  message:
                      '${care.pet.name}\'s recorded care looks consistent with '
                      'their recent history.',
                ),
              ),

            const SizedBox(height: AppTheme.gapXxl),
          ],
        ),
      ),
    );
  }

  static IconData _trendIcon(TrendDirection d) => switch (d) {
        TrendDirection.rising => Icons.trending_up_rounded,
        TrendDirection.falling => Icons.trending_down_rounded,
        TrendDirection.stable => Icons.trending_flat_rounded,
        TrendDirection.insufficientData => Icons.help_outline_rounded,
      };

  static Color _trendColor(TrendDirection d) => switch (d) {
        TrendDirection.rising => AppColors.success,
        TrendDirection.falling => AppColors.warning,
        TrendDirection.stable => AppColors.info,
        TrendDirection.insufficientData => AppColors.inkFaint,
      };
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.label,
    required this.stat,
    required this.color,
    required this.icon,
  });

  final String label;
  final CompletionStat? stat;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bool hasData = stat != null && stat!.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              hasData ? '${stat!.completed}/${stat!.expected}' : 'No data',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: hasData ? color : AppColors.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: hasData ? (stat!.percent / 100).clamp(0.0, 1.0) : 0,
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.13),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CareIconTile(icon: icon, color: color, size: 34),
        const SizedBox(width: AppTheme.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(caption, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
