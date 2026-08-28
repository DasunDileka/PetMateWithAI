import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/feeding.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../care_controller.dart';

/// Feeding schedules and today's completion tracking.
class FeedingScreen extends StatelessWidget {
  const FeedingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final List<FeedingSchedule> schedules = care.schedules;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeding'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppTheme.gapLg,
              bottom: AppTheme.gapMd,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                care.pet.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: schedules.isEmpty
            ? EmptyState(
                icon: CareType.feeding.icon,
                accent: AppColors.feeding,
                title: 'No feeding schedule yet',
                message:
                    'Add ${care.pet.name}\'s meal times to track completion and '
                    'get reminders when a feeding is due.',
                actionLabel: 'Add a feeding time',
                onAction: () => _openForm(context, care),
              )
            : ListView(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                children: <Widget>[
                  _TodaySummary(care: care),
                  const SizedBox(height: AppTheme.gapXl),
                  SectionHeader(
                    title: 'Scheduled meals',
                    subtitle: 'Tap a meal to mark it done for today',
                  ),
                  ...schedules.map((FeedingSchedule s) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                        child: _ScheduleCard(
                          schedule: s,
                          status: care.statusForSchedule(s),
                          care: care,
                          onEdit: () => _openForm(context, care, schedule: s),
                        ),
                      )),
                  const SizedBox(height: AppTheme.gapXxl),
                ],
              ),
      ),
      floatingActionButton: schedules.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context, care),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add meal'),
              backgroundColor: AppColors.feeding,
              foregroundColor: Colors.white,
            ),
    );
  }

  void _openForm(
    BuildContext context,
    CareController care, {
    FeedingSchedule? schedule,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FeedingForm(care: care, schedule: schedule),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.care});

  final CareController care;

  @override
  Widget build(BuildContext context) {
    final int done = care.today?.feedingsCompleted ?? 0;
    final int total = care.schedules.where((s) => s.active).length;
    final double pct = total == 0 ? 0 : done / total;

    return AppCard(
      accent: AppColors.feeding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CareIconTile(
                icon: Icons.today_rounded,
                color: AppColors.feeding,
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Today', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '$done of $total meals completed',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.feeding,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.feeding.withValues(alpha: 0.14),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.feeding),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.status,
    required this.care,
    required this.onEdit,
  });

  final FeedingSchedule schedule;
  final CareStatus status;
  final CareController care;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: schedule.active ? AppColors.feeding : AppColors.inkFaint,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              CareIconTile(icon: status.icon, color: status.color),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            schedule.label,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!schedule.active) ...<Widget>[
                          const SizedBox(width: AppTheme.gapSm),
                          const AppPill(
                            label: 'Paused',
                            color: AppColors.inkFaint,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${schedule.timeLabel} · ${schedule.portionLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Meal options',
                onSelected: (String v) async {
                  switch (v) {
                    case 'edit':
                      onEdit();
                    case 'pause':
                      final bool paused = await runGuarded(
                        context,
                        () => care.repository.updateFeedingSchedule(
                          schedule.copyWith(active: !schedule.active),
                        ),
                      );
                      if (!paused) return;
                      if (schedule.active) {
                        await NotificationService.instance
                            .cancelFeeding(care.pet.id, schedule.id);
                      } else {
                        await NotificationService.instance.scheduleFeeding(
                          pet: care.pet,
                          schedule: schedule.copyWith(active: true),
                        );
                      }
                    case 'delete':
                      if (!context.mounted) return;
                      final bool ok = await confirmAction(
                        context,
                        title: 'Delete ${schedule.label}?',
                        message:
                            'This removes the schedule. Past feeding records are kept.',
                      );
                      if (!ok || !context.mounted) return;
                      final bool removed = await runGuarded(
                        context,
                        () => care.repository.deleteFeedingSchedule(schedule.id),
                      );
                      if (!removed) return;
                      await NotificationService.instance
                          .cancelFeeding(care.pet.id, schedule.id);
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'pause',
                    child: ListTile(
                      leading: Icon(schedule.active
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded),
                      title: Text(schedule.active ? 'Pause' : 'Resume'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger),
                      title: Text('Delete',
                          style: TextStyle(color: AppColors.danger)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (schedule.active) ...<Widget>[
            const Divider(height: AppTheme.gapXl),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Today: ${status.label}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: status.color),
                  ),
                ),
                if (status == CareStatus.completed)
                  TextButton.icon(
                    onPressed: () => runGuarded(
                      context,
                      () => care.repository.setFeedingStatus(
                        schedule: schedule,
                        day: DateTime.now(),
                        status: CareStatus.pending,
                      ),
                    ),
                    icon: const Icon(Icons.undo_rounded, size: 17),
                    label: const Text('Undo'),
                  )
                else ...<Widget>[
                  TextButton(
                    onPressed: () => runGuarded(
                      context,
                      () => care.repository.setFeedingStatus(
                        schedule: schedule,
                        day: DateTime.now(),
                        status: CareStatus.skipped,
                      ),
                    ),
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: AppTheme.gapSm),
                  FilledButton(
                    onPressed: () => runGuarded(
                      context,
                      () => care.repository.markFeedingCompleted(
                        schedule: schedule,
                        day: DateTime.now(),
                      ),
                      successMessage: '${schedule.label} recorded',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.feeding,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.gapLg,
                      ),
                    ),
                    child: const Text('Mark done'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Create/edit sheet for a feeding schedule.
class _FeedingForm extends StatefulWidget {
  const _FeedingForm({required this.care, this.schedule});

  final CareController care;
  final FeedingSchedule? schedule;

  @override
  State<_FeedingForm> createState() => _FeedingFormState();
}

class _FeedingFormState extends State<_FeedingForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _label =
      TextEditingController(text: widget.schedule?.label ?? '');
  late final TextEditingController _food =
      TextEditingController(text: widget.schedule?.foodType ?? '');
  late final TextEditingController _qty = TextEditingController(
    text: widget.schedule?.quantity == null
        ? ''
        : widget.schedule!.quantity!.toStringAsFixed(
            widget.schedule!.quantity! % 1 == 0 ? 0 : 1,
          ),
  );

  late TimeOfDay _time = widget.schedule == null
      ? const TimeOfDay(hour: 8, minute: 0)
      : TimeOfDay(hour: widget.schedule!.hour, minute: widget.schedule!.minute);

  late String _unit = widget.schedule?.unit ?? 'g';
  bool _saving = false;

  static const List<String> _units = <String>['g', 'kg', 'ml', 'cup', 'can'];
  static const List<String> _presets = <String>[
    'Morning', 'Midday', 'Evening', 'Night', 'Treat',
  ];

  @override
  void dispose() {
    _label.dispose();
    _food.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final FeedingSchedule schedule = FeedingSchedule(
      id: widget.schedule?.id ?? '',
      label: _label.text.trim(),
      hour: _time.hour,
      minute: _time.minute,
      foodType: _food.text.trim().isEmpty ? null : _food.text.trim(),
      quantity: double.tryParse(_qty.text.trim()),
      unit: _unit,
      active: widget.schedule?.active ?? true,
      createdAt: widget.schedule?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.schedule == null) {
        final String id = await widget.care.repository.addFeedingSchedule(schedule);
        await NotificationService.instance.scheduleFeeding(
          pet: widget.care.pet,
          schedule: FeedingSchedule(
            id: id,
            label: schedule.label,
            hour: schedule.hour,
            minute: schedule.minute,
            foodType: schedule.foodType,
            quantity: schedule.quantity,
            unit: schedule.unit,
            createdAt: schedule.createdAt,
          ),
        );
      } else {
        await widget.care.repository.updateFeedingSchedule(schedule);
        await NotificationService.instance
            .scheduleFeeding(pet: widget.care.pet, schedule: schedule);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Feeding schedule saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the schedule.', isError: true);
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
              Text(
                widget.schedule == null ? 'Add a meal' : 'Edit meal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _label,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Meal name *',
                  hintText: 'Morning',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                validator: (v) => Validators.required(v, field: 'Meal name'),
              ),
              const SizedBox(height: AppTheme.gapSm),
              Wrap(
                spacing: AppTheme.gapSm,
                children: _presets
                    .map((String p) => ActionChip(
                          label: Text(p),
                          onPressed: () => setState(() => _label.text = p),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (picked == null || !mounted) return;
                  setState(() => _time = picked);
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Time *',
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                  child: Text(_time.format(context)),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _food,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Food type',
                  hintText: 'Dry kibble',
                  prefixIcon: Icon(Icons.set_meal_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        hintText: '200',
                        prefixIcon: Icon(Icons.scale_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.gapMd),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: _units
                          .map((String u) => DropdownMenuItem<String>(
                                value: u,
                                child: Text(u),
                              ))
                          .toList(),
                      onChanged: (String? v) =>
                          setState(() => _unit = v ?? 'g'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.feeding),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save meal'),
              ),
              const SizedBox(height: AppTheme.gapSm),
            ],
          ),
        ),
      ),
    );
  }
}
