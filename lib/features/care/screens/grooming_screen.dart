import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/grooming.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../care_controller.dart';

/// Grooming tasks with their own cadence.
///
/// Completing a task rolls its next due date forward automatically, so the
/// owner maintains a routine by pressing one button rather than re-entering a
/// date each time.
class GroomingScreen extends StatelessWidget {
  const GroomingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final List<GroomingRecord> tasks = care.grooming;

    return Scaffold(
      appBar: AppBar(title: const Text('Grooming')),
      body: SafeArea(
        top: false,
        child: tasks.isEmpty
            ? EmptyState(
                icon: CareType.grooming.icon,
                accent: AppColors.grooming,
                title: 'No grooming tasks yet',
                message:
                    'Add grooming tasks like bathing or nail trimming to keep '
                    '${care.pet.name} on a routine and get reminders.',
                actionLabel: 'Add grooming task',
                onAction: () => _openForm(context, care),
              )
            : ListView(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                children: <Widget>[
                  ...tasks.map((GroomingRecord g) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                        child: _GroomingCard(
                          record: g,
                          care: care,
                          onEdit: () => _openForm(context, care, record: g),
                        ),
                      )),
                  const SizedBox(height: 96),
                ],
              ),
      ),
      floatingActionButton: tasks.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context, care),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add task'),
              backgroundColor: AppColors.grooming,
              foregroundColor: Colors.white,
            ),
    );
  }

  void _openForm(
    BuildContext context,
    CareController care, {
    GroomingRecord? record,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _GroomingForm(care: care, record: record),
      ),
    );
  }
}

class _GroomingCard extends StatelessWidget {
  const _GroomingCard({
    required this.record,
    required this.care,
    required this.onEdit,
  });

  final GroomingRecord record;
  final CareController care;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        record.isOverdue ? AppColors.danger : AppColors.grooming;

    return AppCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CareIconTile(icon: record.type.icon, color: AppColors.grooming),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(record.type.label,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      record.lastCompletedAt == null
                          ? 'Never completed'
                          : 'Last done ${_date(record.lastCompletedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Task options',
                onSelected: (String v) async {
                  if (v == 'edit') {
                    onEdit();
                  } else if (v == 'delete') {
                    final bool ok = await confirmAction(
                      context,
                      title: 'Delete ${record.type.label}?',
                      message: 'This grooming task and its reminder will be removed.',
                    );
                    if (!ok) return;
                    await care.repository.deleteGrooming(record.id);
                    await NotificationService.instance
                        .cancelGrooming(care.pet.id, record.id);
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
          const SizedBox(height: AppTheme.gapSm),
          Row(
            children: <Widget>[
              AppPill(
                label: record.dueLabel,
                color: accent,
                icon: Icons.schedule_rounded,
              ),
              const SizedBox(width: AppTheme.gapSm),
              AppPill(
                label: 'Every ${record.effectiveIntervalDays} days',
                color: AppColors.inkFaint,
                icon: Icons.repeat_rounded,
              ),
            ],
          ),
          const Divider(height: AppTheme.gapXl),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  record.nextDueAt == null
                      ? 'Mark done to start the schedule'
                      : 'Next: ${_date(record.nextDueAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final GroomingRecord updated =
                      record.completedAt(DateTime.now());
                  await care.repository.updateGrooming(updated);
                  await NotificationService.instance.scheduleGrooming(
                    pet: care.pet,
                    grooming: updated,
                  );
                  if (context.mounted) {
                    showAppSnack(context, '${record.type.label} completed');
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Mark done'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.grooming,
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gapLg),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _GroomingForm extends StatefulWidget {
  const _GroomingForm({required this.care, this.record});

  final CareController care;
  final GroomingRecord? record;

  @override
  State<_GroomingForm> createState() => _GroomingFormState();
}

class _GroomingFormState extends State<_GroomingForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late GroomingType _type = widget.record?.type ?? GroomingType.bath;
  late final TextEditingController _interval = TextEditingController(
    text: (widget.record?.effectiveIntervalDays ?? GroomingType.bath.defaultIntervalDays)
        .toString(),
  );
  late final TextEditingController _notes =
      TextEditingController(text: widget.record?.notes ?? '');
  late DateTime? _lastDone = widget.record?.lastCompletedAt;

  bool _saving = false;

  @override
  void dispose() {
    _interval.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final int interval =
        int.tryParse(_interval.text.trim()) ?? _type.defaultIntervalDays;

    // Next due follows from the last completion plus the cadence; with no
    // completion recorded yet the task starts due today.
    final DateTime nextDue = _lastDone == null
        ? DateTime.now()
        : DateTime(_lastDone!.year, _lastDone!.month, _lastDone!.day)
            .add(Duration(days: interval));

    final GroomingRecord record = GroomingRecord(
      id: widget.record?.id ?? '',
      type: _type,
      lastCompletedAt: _lastDone,
      nextDueAt: nextDue,
      intervalDays: interval,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: widget.record?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.record == null) {
        final String id = await widget.care.repository.addGrooming(record);
        await NotificationService.instance.scheduleGrooming(
          pet: widget.care.pet,
          grooming: GroomingRecord(
            id: id,
            type: record.type,
            lastCompletedAt: record.lastCompletedAt,
            nextDueAt: record.nextDueAt,
            intervalDays: record.intervalDays,
            notes: record.notes,
            createdAt: record.createdAt,
          ),
        );
      } else {
        await widget.care.repository.updateGrooming(record);
        await NotificationService.instance
            .scheduleGrooming(pet: widget.care.pet, grooming: record);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Grooming task saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the task.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.gapXl),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.record == null ? 'Add grooming task' : 'Edit task',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.gapLg),

              Wrap(
                spacing: AppTheme.gapSm,
                runSpacing: AppTheme.gapSm,
                children: GroomingType.values.map((GroomingType t) {
                  return ChoiceChip(
                    avatar: Icon(t.icon, size: 16),
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _interval.text = t.defaultIntervalDays.toString();
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Repeat every (days) *',
                  prefixIcon: Icon(Icons.repeat_rounded),
                  suffixText: 'days',
                ),
                validator: (String? v) {
                  final int? n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number of days.';
                  if (n < 1) return 'Must be at least 1 day.';
                  if (n > 365) return 'Must be 365 days or fewer.';
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: () async {
                  final DateTime now = DateTime.now();
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _lastDone ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: now,
                    helpText: 'Last completed',
                  );
                  if (picked == null || !mounted) return;
                  setState(() => _lastDone = picked);
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Last completed',
                    prefixIcon: const Icon(Icons.event_available_rounded),
                    suffixIcon: _lastDone == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _lastDone = null),
                            tooltip: 'Clear',
                          ),
                  ),
                  child: Text(
                    _lastDone == null
                        ? 'Not yet completed'
                        : '${_lastDone!.day}/${_lastDone!.month}/${_lastDone!.year}',
                    style: TextStyle(
                      color: _lastDone == null
                          ? AppColors.inkFaint
                          : Theme.of(context).colorScheme.onSurface,
                    ),
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
                  hintText: 'Use sensitive-skin shampoo',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.grooming),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save task'),
              ),
              const SizedBox(height: AppTheme.gapSm),
            ],
          ),
        ),
      ),
    );
  }
}
