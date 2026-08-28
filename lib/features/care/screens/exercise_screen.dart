import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/exercise.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../analytics/care_analytics.dart';
import '../../analytics/widgets/activity_chart.dart';
import '../care_controller.dart';
import 'walk_tracker_screen.dart';

/// Exercise log: record sessions manually or track a live GPS walk.
class ExerciseScreen extends StatelessWidget {
  const ExerciseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final List<ExerciseRecord> records = care.exercise;
    final TrendResult? trend = care.trend;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercise')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Today',
                    value: '${care.today?.exerciseMinutes ?? 0} min',
                    icon: Icons.today_rounded,
                    color: AppColors.exercise,
                  ),
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: StatTile(
                    label: 'Daily average',
                    value: trend != null && trend.hasData
                        ? '${trend.mean.round()} min'
                        : '—',
                    caption: trend?.shortLabel,
                    icon: Icons.trending_up_rounded,
                    color: AppColors.exercise,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.gapXl),

            if (trend != null && trend.hasData) ...<Widget>[
              SectionHeader(
                title: 'Last 7 days',
                subtitle: 'Minutes of recorded activity per day',
                icon: Icons.bar_chart_rounded,
              ),
              AppCard(
                child: SizedBox(
                  height: 170,
                  child: ActivityChart(
                    series: trend.series.length > 7
                        ? trend.series.sublist(trend.series.length - 7)
                        : trend.series,
                    color: AppColors.exercise,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.gapXl),
            ],

            SectionHeader(
              title: 'Recent sessions',
              subtitle: records.isEmpty
                  ? null
                  : '${records.length} in the last 14 days',
              icon: Icons.history_rounded,
            ),

            if (records.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: CareType.exercise.icon,
                  accent: AppColors.exercise,
                  title: 'No exercise recorded',
                  message:
                      'Record a walk, run or play session to start building '
                      '${care.pet.name}\'s activity history.',
                  compact: true,
                ),
              )
            else
              ...records.map((ExerciseRecord r) => Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                    child: _ExerciseCard(record: r, care: care),
                  )),

            const SizedBox(height: 96),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'track_walk',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WalkTrackerScreen(care: care),
              ),
            ),
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            tooltip: 'Track a walk with GPS',
            child: const Icon(Icons.my_location_rounded),
          ),
          const SizedBox(height: AppTheme.gapMd),
          FloatingActionButton.extended(
            heroTag: 'add_exercise',
            onPressed: () => _openForm(context, care),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Record'),
            backgroundColor: AppColors.exercise,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, CareController care) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ExerciseForm(care: care),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.record, required this.care});

  final ExerciseRecord record;
  final CareController care;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: AppColors.exercise,
      child: Row(
        children: <Widget>[
          CareIconTile(icon: record.type.icon, color: AppColors.exercise),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(record.type.label,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (record.wasTracked) ...<Widget>[
                      const SizedBox(width: AppTheme.gapSm),
                      const AppPill(
                        label: 'GPS',
                        color: AppColors.navy,
                        icon: Icons.my_location_rounded,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.durationMinutes} min'
                  '${record.distanceKm != null && record.distanceKm! > 0 ? ' · ${record.distanceLabel}' : ''}'
                  ' · ${_when(record.occurredAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if ((record.notes ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    record.notes!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete session',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () async {
              final bool ok = await confirmAction(
                context,
                title: 'Delete this session?',
                message:
                    '${record.type.label} of ${record.durationMinutes} minutes '
                    'will be removed from the activity history.',
              );
              if (!ok || !context.mounted) return;
              await runGuarded(
                context,
                () => care.repository.deleteExercise(record.id),
                successMessage: 'Session deleted',
              );
            },
          ),
        ],
      ),
    );
  }

  static String _when(DateTime d) {
    final DateTime now = DateTime.now();
    final int days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    final String time =
        '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
    if (days == 0) return 'Today, $time';
    if (days == 1) return 'Yesterday, $time';
    return '$days days ago';
  }
}

/// Manual exercise entry.
class _ExerciseForm extends StatefulWidget {
  const _ExerciseForm({required this.care});

  final CareController care;

  @override
  State<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends State<_ExerciseForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _duration = TextEditingController(text: '20');
  final TextEditingController _notes = TextEditingController();

  ExerciseType _type = ExerciseType.walk;
  DateTime _when = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _duration.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await widget.care.repository.addExercise(ExerciseRecord(
        id: '',
        type: _type,
        durationMinutes: int.parse(_duration.text.trim()),
        occurredAt: _when,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ));

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, '${_type.label} recorded');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the session.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Record exercise',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppTheme.gapLg),

              Wrap(
                spacing: AppTheme.gapSm,
                runSpacing: AppTheme.gapSm,
                children: ExerciseType.values.map((ExerciseType t) {
                  return ChoiceChip(
                    avatar: Icon(t.icon, size: 16),
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes) *',
                  prefixIcon: Icon(Icons.timer_outlined),
                  suffixText: 'min',
                ),
                validator: Validators.duration,
              ),
              const SizedBox(height: AppTheme.gapSm),
              Wrap(
                spacing: AppTheme.gapSm,
                children: <int>[10, 15, 20, 30, 45, 60]
                    .map((int m) => ActionChip(
                          label: Text('$m'),
                          onPressed: () =>
                              setState(() => _duration.text = m.toString()),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: () async {
                  // `_when` can sit slightly ahead of now — the field defaults
                  // to the moment the sheet opened, and the time picker will
                  // happily accept a later hour today. showDatePicker asserts
                  // when initialDate is after lastDate, so both ends are pinned
                  // to the same instant and the initial value clamped into it.
                  final DateTime now = DateTime.now();
                  final DateTime initial = _when.isAfter(now) ? now : _when;
                  final DateTime? d = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: now.subtract(const Duration(days: 60)),
                    lastDate: now,
                  );
                  if (d == null || !context.mounted) return;
                  final TimeOfDay? t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_when),
                  );
                  // A cancelled time picker keeps the existing time but still
                  // applies the chosen date, so only `mounted` is checked here.
                  if (!mounted) return;
                  setState(() {
                    _when = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      t?.hour ?? _when.hour,
                      t?.minute ?? _when.minute,
                    );
                  });
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'When',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  child: Text(
                    '${_when.day}/${_when.month}/${_when.year} at '
                    '${_when.hour.toString().padLeft(2, '0')}:'
                    '${_when.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Energetic, met other dogs at the park',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => Validators.notes(v, max: 300),
              ),
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.exercise),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save session'),
              ),
              const SizedBox(height: AppTheme.gapSm),
            ],
          ),
        ),
      ),
    );
  }
}
