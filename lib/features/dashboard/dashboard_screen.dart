import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/ui_kit.dart';
import '../analytics/care_analytics.dart';
import '../analytics/screens/analytics_screen.dart';
import '../auth/auth_controller.dart';
import '../care/care_controller.dart';
import '../care/screens/exercise_screen.dart';
import '../care/screens/feeding_screen.dart';
import '../pets/pet_controller.dart';
import '../profile/profile_screen.dart';
import 'widgets/ai_insight_card.dart';
import 'widgets/pet_switcher.dart';

/// The app's home screen: today's care at a glance, what is coming up, and the
/// AI's read on the pet's recent pattern.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final PetController pets = context.watch<PetController>();
    final AuthController auth = context.watch<AuthController>();
    final Pet pet = care.pet;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          // Firestore listeners already keep this live; pull-to-refresh exists
          // to force a fresh AI insight, which is deliberately cached.
          onRefresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Header(
                  greeting: _greeting(auth.profile?.firstName),
                  onProfile: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: PetSwitcher(
                  pets: pets.pets,
                  activeId: pet.id,
                  onSelect: (String id) {
                    pets.selectPet(id);
                    auth.setActivePet(id);
                  },
                ),
              ),

              if (care.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: LoadingView(message: 'Loading today\'s care…'),
                )
              else ...<Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.gapLg,
                    AppTheme.gapLg,
                    AppTheme.gapLg,
                    0,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      if (care.error != null) ...<Widget>[
                        InlineNotice(
                          message: care.error!,
                          onDismiss: care.clearError,
                        ),
                        const SizedBox(height: AppTheme.gapLg),
                      ],

                      const AiInsightCard(),
                      const SizedBox(height: AppTheme.gapXl),

                      SectionHeader(
                        title: 'Today\'s Care',
                        subtitle: _dateLabel(DateTime.now()),
                        icon: Icons.today_rounded,
                      ),
                      _TodayCare(care: care),
                      const SizedBox(height: AppTheme.gapXl),

                      SectionHeader(
                        title: 'Upcoming',
                        icon: Icons.event_rounded,
                      ),
                      _Upcoming(care: care),
                      const SizedBox(height: AppTheme.gapXl),

                      SectionHeader(
                        title: 'This Week',
                        actionLabel: 'Details',
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AnalyticsScreen(),
                          ),
                        ),
                        icon: Icons.insights_rounded,
                      ),
                      _WeekStats(care: care),

                      const SizedBox(height: AppTheme.gapXxl),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _greeting(String? name) {
    final int h = DateTime.now().hour;
    final String part = h < 12
        ? 'Good morning'
        : h < 18
            ? 'Good afternoon'
            : 'Good evening';
    return name == null ? part : '$part, $name';
  }

  static String _dateLabel(DateTime d) {
    const List<String> months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const List<String> days = <String>[
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.onProfile});

  final String greeting;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapLg,
        AppTheme.gapMd,
        AppTheme.gapSm,
        0,
      ),
      child: Row(
        children: <Widget>[
          const PetMateMark(size: 38),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greeting,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'PetMate · Your AI Pet Care Companion',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onProfile,
            icon: const Icon(Icons.account_circle_outlined, size: 28),
            tooltip: 'Profile and settings',
          ),
        ],
      ),
    );
  }
}

/// Today's four care domains, each with its current state and a direct action.
class _TodayCare extends StatelessWidget {
  const _TodayCare({required this.care});

  final CareController care;

  @override
  Widget build(BuildContext context) {
    final TodaySnapshot? today = care.today;
    if (today == null) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        _FeedingTile(care: care, today: today),
        const SizedBox(height: AppTheme.gapMd),
        _ExerciseTile(care: care, today: today),
        const SizedBox(height: AppTheme.gapMd),
        _MedicineTile(care: care, today: today),
        const SizedBox(height: AppTheme.gapMd),
        _GroomingTile(care: care, today: today),
      ],
    );
  }
}

class _FeedingTile extends StatelessWidget {
  const _FeedingTile({required this.care, required this.today});

  final CareController care;
  final TodaySnapshot today;

  @override
  Widget build(BuildContext context) {
    final List<FeedingSchedule> schedules = care.schedules
        .where((s) => s.active)
        .toList(growable: false);

    return AppCard(
      accent: AppColors.feeding,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FeedingScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CareIconTile(
                icon: CareType.feeding.icon,
                color: AppColors.feeding,
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Feeding',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      schedules.isEmpty
                          ? 'No schedule set up'
                          : '${today.feedingsCompleted} of ${schedules.length} completed',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (schedules.isNotEmpty)
                AppPill(
                  label: today.allFeedingsDone ? 'Done' : 'Pending',
                  color: today.allFeedingsDone
                      ? AppColors.success
                      : AppColors.warning,
                ),
            ],
          ),
          if (schedules.isEmpty) ...<Widget>[
            const SizedBox(height: AppTheme.gapMd),
            Text(
              'Add a feeding schedule to track meals and get reminders.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...<Widget>[
            const SizedBox(height: AppTheme.gapMd),
            ...schedules.take(3).map((FeedingSchedule s) {
              final CareStatus status = care.statusForSchedule(s);
              return Padding(
                padding: const EdgeInsets.only(top: AppTheme.gapSm),
                child: Row(
                  children: <Widget>[
                    Icon(status.icon, size: 17, color: status.color),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: Text(
                        '${s.label} · ${s.timeLabel}',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (status != CareStatus.completed)
                      TextButton(
                        onPressed: () => runGuarded(
                          context,
                          () => care.repository.markFeedingCompleted(
                            schedule: s,
                            day: DateTime.now(),
                          ),
                          successMessage: '${s.label} marked as done',
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Mark done'),
                      )
                    else
                      Text(
                        'Done',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: AppColors.success),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.care, required this.today});

  final CareController care;
  final TodaySnapshot today;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: AppColors.exercise,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ExerciseScreen()),
      ),
      child: Row(
        children: <Widget>[
          CareIconTile(icon: CareType.exercise.icon, color: AppColors.exercise),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Exercise', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  today.hasExercise
                      ? '${today.exerciseMinutes} minutes recorded today'
                      : 'No exercise recorded today',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExerciseScreen()),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapLg),
              backgroundColor: AppColors.exercise.withValues(alpha: 0.12),
              foregroundColor: AppColors.exercise,
            ),
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }
}

class _MedicineTile extends StatelessWidget {
  const _MedicineTile({required this.care, required this.today});

  final CareController care;
  final TodaySnapshot today;

  @override
  Widget build(BuildContext context) {
    final List<({Medicine medicine, DateTime dueAt, CareStatus status})> doses =
        care.dosesDueToday();

    return AppCard(
      accent: AppColors.medicine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CareIconTile(
                icon: CareType.medicine.icon,
                color: AppColors.medicine,
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Medicine',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      doses.isEmpty
                          ? 'None due today'
                          : '${today.dosesTaken} of ${doses.length} doses given',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (doses.isNotEmpty)
                AppPill(
                  label: today.medicationOutstanding ? 'Due' : 'Done',
                  color: today.medicationOutstanding
                      ? AppColors.warning
                      : AppColors.success,
                ),
            ],
          ),
          ...doses.take(3).map((d) => Padding(
                padding: const EdgeInsets.only(top: AppTheme.gapSm),
                child: Row(
                  children: <Widget>[
                    Icon(d.status.icon, size: 17, color: d.status.color),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: Text(
                        '${d.medicine.name} · ${_time(d.dueAt)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (d.status != CareStatus.completed)
                      TextButton(
                        onPressed: () => runGuarded(
                          context,
                          () => care.repository.setDoseStatus(
                            medicine: d.medicine,
                            dueAt: d.dueAt,
                            status: CareStatus.completed,
                          ),
                          successMessage: 'Dose recorded',
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Given'),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  static String _time(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _GroomingTile extends StatelessWidget {
  const _GroomingTile({required this.care, required this.today});

  final CareController care;
  final TodaySnapshot today;

  @override
  Widget build(BuildContext context) {
    final GroomingRecord? next = today.nextGrooming;

    return AppCard(
      accent: AppColors.grooming,
      child: Row(
        children: <Widget>[
          CareIconTile(icon: CareType.grooming.icon, color: AppColors.grooming),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Grooming', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  next == null
                      ? 'No grooming tasks set up'
                      : '${next.type.label} · ${next.dueLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (next != null)
            AppPill(
              label: next.isOverdue ? 'Overdue' : 'Scheduled',
              color: next.isOverdue ? AppColors.danger : AppColors.grooming,
            ),
        ],
      ),
    );
  }
}

/// Forward-looking items: vaccination and the next vet appointment.
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.care});

  final CareController care;

  @override
  Widget build(BuildContext context) {
    final TodaySnapshot? today = care.today;
    if (today == null) return const SizedBox.shrink();

    final Vaccination? vac = today.nextVaccination;
    final Appointment? appt = today.nextAppointment;

    if (vac == null && appt == null) {
      return AppCard(
        child: EmptyState(
          icon: Icons.event_available_rounded,
          title: 'Nothing scheduled',
          message:
              'No upcoming vaccinations or veterinary appointments for ${care.pet.name}.',
          compact: true,
        ),
      );
    }

    return Column(
      children: <Widget>[
        if (appt != null)
          AppCard(
            accent: AppColors.vet,
            child: Row(
              children: <Widget>[
                CareIconTile(
                  icon: CareType.appointment.icon,
                  color: AppColors.vet,
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Vet appointment',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${appt.reason} · ${appt.whenLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (appt != null && vac != null) const SizedBox(height: AppTheme.gapMd),
        if (vac != null)
          AppCard(
            accent: AppColors.vaccination,
            child: Row(
              children: <Widget>[
                CareIconTile(
                  icon: CareType.vaccination.icon,
                  color: AppColors.vaccination,
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Vaccination',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${vac.vaccineName} · ${vac.dueLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Three headline figures for the week, each computed by [CareAnalytics].
class _WeekStats extends StatelessWidget {
  const _WeekStats({required this.care});

  final CareController care;

  @override
  Widget build(BuildContext context) {
    final CompletionStat? feeding = care.feedingStat;
    final CompletionStat? meds = care.medicationStat;
    final TrendResult? trend = care.trend;

    // The three tiles are stretched to a common height so the row reads as one
    // unit. Stretch has to resolve against a bounded height, and this row sits
    // in a sliver list where height is unbounded — IntrinsicHeight supplies
    // that bound. Without it the row cannot lay out and the tiles silently
    // vanish, leaving the section heading above empty space.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'Feeding',
              value: feeding != null && feeding.hasData
                  ? '${feeding.percent.round()}%'
                  : '—',
              caption: feeding?.label ?? 'No schedule',
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
              label: 'Activity',
              value: trend != null && trend.hasData
                  ? '${trend.mean.round()}m'
                  : '—',
              caption: trend?.shortLabel ?? 'No data',
              icon: CareType.exercise.icon,
              color: AppColors.exercise,
            ),
          ),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: StatTile(
              label: 'Medicine',
              value: meds != null && meds.hasData
                  ? '${meds.percent.round()}%'
                  : '—',
              caption: meds?.label ?? 'None due',
              icon: CareType.medicine.icon,
              color: AppColors.medicine,
              progress:
                  meds != null && meds.hasData ? meds.percent / 100 : null,
            ),
          ),
        ],
      ),
    );
  }
}
