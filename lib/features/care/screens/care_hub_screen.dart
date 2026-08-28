import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../calendar/calendar_screen.dart';
import '../../history/care_history_screen.dart';
import '../care_controller.dart';
import 'exercise_screen.dart';
import 'feeding_screen.dart';
import 'grooming_screen.dart';
import 'medicine_screen.dart';
import 'vaccination_screen.dart';

/// Entry point to every care module for the selected pet.
///
/// A hub rather than five more bottom-navigation items: the brief warns against
/// crowding the navigation bar, and grouping the care domains behind one tab
/// keeps the top-level structure to five clear destinations.
class CareHubScreen extends StatelessWidget {
  const CareHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care'),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CalendarScreen()),
            ),
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Care calendar',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          children: <Widget>[
            Text(
              'Caring for ${care.pet.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.gapXs),
            Text(
              care.pet.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.gapXl),

            _CareModuleTile(
              type: CareType.feeding,
              title: 'Feeding',
              subtitle: care.schedules.isEmpty
                  ? 'No schedule set up'
                  : _mealCount(care.schedules.where((s) => s.active).length),
              trailing: care.today == null
                  ? null
                  : '${care.today!.feedingsCompleted}/${care.today!.feedingsScheduled} today',
              onTap: () => _open(context, const FeedingScreen()),
            ),
            _CareModuleTile(
              type: CareType.exercise,
              title: 'Exercise',
              subtitle: 'Walks, runs, play and training',
              trailing: care.today == null
                  ? null
                  : '${care.today!.exerciseMinutes} min today',
              onTap: () => _open(context, const ExerciseScreen()),
            ),
            _CareModuleTile(
              type: CareType.medicine,
              title: 'Medicine',
              subtitle: care.medicines.isEmpty
                  ? 'No medication recorded'
                  : '${care.medicines.where((m) => m.isActive).length} active course(s)',
              trailing: care.today == null || care.today!.dosesDue == 0
                  ? null
                  : '${care.today!.dosesTaken}/${care.today!.dosesDue} today',
              onTap: () => _open(context, const MedicineScreen()),
            ),
            _CareModuleTile(
              type: CareType.vaccination,
              title: 'Vaccination',
              subtitle: care.vaccinations.isEmpty
                  ? 'No vaccinations recorded'
                  : '${care.vaccinations.length} recorded',
              trailing: care.today?.nextVaccination?.dueLabel,
              trailingColor: (care.today?.nextVaccination?.isOverdue ?? false)
                  ? AppColors.danger
                  : null,
              onTap: () => _open(context, const VaccinationScreen()),
            ),
            _CareModuleTile(
              type: CareType.grooming,
              title: 'Grooming',
              subtitle: care.grooming.isEmpty
                  ? 'No grooming tasks set up'
                  : '${care.grooming.length} task(s)',
              trailing: care.today?.nextGrooming?.dueLabel,
              trailingColor: (care.today?.nextGrooming?.isOverdue ?? false)
                  ? AppColors.danger
                  : null,
              onTap: () => _open(context, const GroomingScreen()),
            ),

            const SizedBox(height: AppTheme.gapXl),
            SectionHeader(
              title: 'Records',
              icon: Icons.history_rounded,
            ),

            AppCard(
              onTap: () => _open(context, const CareHistoryScreen()),
              child: Row(
                children: <Widget>[
                  const CareIconTile(
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: AppTheme.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Complete care history',
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          'Every feeding, walk, dose, vaccination and visit',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.inkFaint),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapMd),
            AppCard(
              onTap: () => _open(context, const CalendarScreen()),
              child: Row(
                children: <Widget>[
                  const CareIconTile(
                    icon: Icons.calendar_month_rounded,
                    color: AppColors.sky,
                  ),
                  const SizedBox(width: AppTheme.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Care calendar',
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          'See past and upcoming care by date',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.inkFaint),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXxl),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  static String _mealCount(int n) =>
      n == 1 ? '1 scheduled meal' : '$n scheduled meals';
}

class _CareModuleTile extends StatelessWidget {
  const _CareModuleTile({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.trailingColor,
  });

  final CareType type;
  final String title;
  final String subtitle;
  final String? trailing;

  /// Overrides the domain colour for the status text. Used so an overdue task
  /// does not read as healthy: the grooming teal and the vaccination blue both
  /// look like reassurance next to the words "Overdue by 5 days".
  final Color? trailingColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      child: AppCard(
        accent: type.color,
        onTap: onTap,
        child: Row(
          children: <Widget>[
            CareIconTile(icon: type.icon, color: type.color, size: 44),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppTheme.gapSm),
              Flexible(
                child: Text(
                  trailing!,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: trailingColor ?? type.color),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                ),
              ),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
