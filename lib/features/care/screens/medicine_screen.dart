import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/medicine.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../care_controller.dart';

/// Medication courses and per-dose tracking.
///
/// PetMate records exactly what the owner was prescribed and whether each dose
/// was given. It never suggests a medicine, a dose, or a change to either —
/// that boundary is enforced in the AI layer and reflected in this UI's copy.
class MedicineScreen extends StatelessWidget {
  const MedicineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final List<Medicine> medicines = care.medicines;
    final List<({Medicine medicine, DateTime dueAt, CareStatus status})> today =
        care.dosesDueToday();

    return Scaffold(
      appBar: AppBar(title: const Text('Medicine')),
      body: SafeArea(
        top: false,
        child: medicines.isEmpty
            ? EmptyState(
                icon: CareType.medicine.icon,
                accent: AppColors.medicine,
                title: 'No medication recorded',
                message:
                    'Add a medicine your vet has prescribed for ${care.pet.name} '
                    'to track doses and get reminders.',
                actionLabel: 'Add medicine',
                onAction: () => _openForm(context, care),
              )
            : ListView(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                children: <Widget>[
                  if (today.isNotEmpty) ...<Widget>[
                    SectionHeader(
                      title: 'Due today',
                      subtitle: 'Mark each dose once it has been given',
                      icon: Icons.today_rounded,
                    ),
                    ...today.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                          child: _DoseCard(dose: d, care: care),
                        )),
                    const SizedBox(height: AppTheme.gapXl),
                  ],

                  SectionHeader(
                    title: 'Medication',
                    subtitle: '${medicines.where((m) => m.isActive).length} active',
                    icon: Icons.medication_rounded,
                  ),
                  ...medicines.map((Medicine m) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                        child: _MedicineCard(
                          medicine: m,
                          care: care,
                          onEdit: () => _openForm(context, care, medicine: m),
                        ),
                      )),
                  const SizedBox(height: 96),
                ],
              ),
      ),
      floatingActionButton: medicines.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context, care),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add medicine'),
              backgroundColor: AppColors.medicine,
              foregroundColor: Colors.white,
            ),
    );
  }

  void _openForm(BuildContext context, CareController care, {Medicine? medicine}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MedicineForm(care: care, medicine: medicine),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose, required this.care});

  final ({Medicine medicine, DateTime dueAt, CareStatus status}) dose;
  final CareController care;

  @override
  Widget build(BuildContext context) {
    final bool done = dose.status == CareStatus.completed;

    return AppCard(
      accent: dose.status.color,
      child: Row(
        children: <Widget>[
          CareIconTile(icon: dose.status.icon, color: dose.status.color),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(dose.medicine.name,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${dose.medicine.dosage} · due ${_time(dose.dueAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (done)
            TextButton(
              onPressed: () => runGuarded(
                context,
                () => care.repository.setDoseStatus(
                  medicine: dose.medicine,
                  dueAt: dose.dueAt,
                  status: CareStatus.pending,
                ),
              ),
              child: const Text('Undo'),
            )
          else
            FilledButton(
              onPressed: () => runGuarded(
                context,
                () => care.repository.setDoseStatus(
                  medicine: dose.medicine,
                  dueAt: dose.dueAt,
                  status: CareStatus.completed,
                ),
                successMessage: 'Dose recorded',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.medicine,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapLg),
              ),
              child: const Text('Given'),
            ),
        ],
      ),
    );
  }

  static String _time(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _MedicineCard extends StatelessWidget {
  const _MedicineCard({
    required this.medicine,
    required this.care,
    required this.onEdit,
  });

  final Medicine medicine;
  final CareController care;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final int? remaining = medicine.daysRemaining;

    return AppCard(
      accent: medicine.isActive ? AppColors.medicine : AppColors.inkFaint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(medicine.name,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${medicine.dosage} · ${medicine.frequency.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AppPill(
                label: medicine.status.label,
                color: medicine.status.color,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Medicine options',
                onSelected: (String v) async {
                  switch (v) {
                    case 'edit':
                      onEdit();
                    case 'complete':
                      final bool completed = await runGuarded(
                        context,
                        () => care.repository.updateMedicine(
                          medicine.copyWith(status: MedicineStatus.completed),
                        ),
                      );
                      if (!completed) return;
                      await NotificationService.instance
                          .cancelMedicine(care.pet.id, medicine.id);
                    case 'delete':
                      if (!context.mounted) return;
                      final bool ok = await confirmAction(
                        context,
                        title: 'Delete ${medicine.name}?',
                        message:
                            'The course and its reminders will be removed. '
                            'Recorded doses are kept in the history.',
                      );
                      if (!ok || !context.mounted) return;
                      final bool removed = await runGuarded(
                        context,
                        () => care.repository.deleteMedicine(medicine.id),
                      );
                      if (!removed) return;
                      await NotificationService.instance
                          .cancelMedicine(care.pet.id, medicine.id);
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
                  if (medicine.status == MedicineStatus.active)
                    const PopupMenuItem<String>(
                      value: 'complete',
                      child: ListTile(
                        leading: Icon(Icons.task_alt_rounded),
                        title: Text('Mark course complete'),
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
          Wrap(
            spacing: AppTheme.gapSm,
            runSpacing: AppTheme.gapSm,
            children: <Widget>[
              AppPill(
                label: 'From ${_date(medicine.startDate)}',
                color: AppColors.inkFaint,
                icon: Icons.event_rounded,
              ),
              if (medicine.endDate != null)
                AppPill(
                  label: remaining == null
                      ? 'Until ${_date(medicine.endDate!)}'
                      : remaining == 0
                          ? 'Last day'
                          : '$remaining days left',
                  color: AppColors.medicine,
                  icon: Icons.hourglass_bottom_rounded,
                ),
              if (medicine.veterinarianName != null)
                AppPill(
                  label: medicine.veterinarianName!,
                  color: AppColors.vet,
                  icon: Icons.person_outline_rounded,
                ),
            ],
          ),
          if ((medicine.notes ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Text(
              medicine.notes!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _MedicineForm extends StatefulWidget {
  const _MedicineForm({required this.care, this.medicine});

  final CareController care;
  final Medicine? medicine;

  @override
  State<_MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<_MedicineForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.medicine?.name ?? '');
  late final TextEditingController _dosage =
      TextEditingController(text: widget.medicine?.dosage ?? '');
  late final TextEditingController _vet =
      TextEditingController(text: widget.medicine?.veterinarianName ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.medicine?.notes ?? '');

  late MedicineFrequency _frequency =
      widget.medicine?.frequency ?? MedicineFrequency.onceDaily;
  late DateTime _start = widget.medicine?.startDate ?? DateTime.now();
  late DateTime? _end = widget.medicine?.endDate;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _vet.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // The two dates are pickers, not form fields, so `validate()` never sees
    // them. Without this a course could end before it started, which made
    // `daysRemaining` negative and the card read "-914 days left".
    final DateTime? end = _end;
    if (end != null && end.isBefore(DateTime(_start.year, _start.month, _start.day))) {
      showAppSnack(
        context,
        'The end date cannot be before the start date.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);

    final Medicine medicine = Medicine(
      id: widget.medicine?.id ?? '',
      name: _name.text.trim(),
      dosage: _dosage.text.trim(),
      frequency: _frequency,
      startDate: _start,
      endDate: _end,
      status: widget.medicine?.status ?? MedicineStatus.active,
      veterinarianName: _vet.text.trim().isEmpty ? null : _vet.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: widget.medicine?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.medicine == null) {
        final String id = await widget.care.repository.addMedicine(medicine);
        // Reminder ids are derived from the medicine's document id, so the
        // freshly assigned id has to be carried into the scheduler.
        await NotificationService.instance.scheduleMedicine(
          pet: widget.care.pet,
          medicine: Medicine(
            id: id,
            name: medicine.name,
            dosage: medicine.dosage,
            frequency: medicine.frequency,
            startDate: medicine.startDate,
            endDate: medicine.endDate,
            status: medicine.status,
            veterinarianId: medicine.veterinarianId,
            veterinarianName: medicine.veterinarianName,
            notes: medicine.notes,
            createdAt: medicine.createdAt,
          ),
        );
      } else {
        await widget.care.repository.updateMedicine(medicine);
        await NotificationService.instance
            .scheduleMedicine(pet: widget.care.pet, medicine: medicine);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Medicine saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the medicine.', isError: true);
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
                widget.medicine == null ? 'Add medicine' : 'Edit medicine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.gapXs),
              Text(
                'Enter exactly what your veterinarian prescribed. PetMate does '
                'not suggest medicines or dosages.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Medicine name *',
                  prefixIcon: Icon(Icons.medication_outlined),
                ),
                validator: (v) => Validators.required(v, field: 'Medicine name'),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _dosage,
                decoration: const InputDecoration(
                  labelText: 'Dosage *',
                  hintText: '1 tablet (50 mg)',
                  prefixIcon: Icon(Icons.straighten_rounded),
                ),
                validator: (v) => Validators.required(v, field: 'Dosage'),
              ),
              const SizedBox(height: AppTheme.gapLg),

              DropdownButtonFormField<MedicineFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency *',
                  prefixIcon: Icon(Icons.repeat_rounded),
                ),
                items: MedicineFrequency.values
                    .map((MedicineFrequency f) =>
                        DropdownMenuItem<MedicineFrequency>(
                          value: f,
                          child: Text(f.label),
                        ))
                    .toList(),
                onChanged: (MedicineFrequency? v) =>
                    setState(() => _frequency = v ?? MedicineFrequency.onceDaily),
              ),
              const SizedBox(height: AppTheme.gapLg),

              Row(
                children: <Widget>[
                  Expanded(
                    child: _DateField(
                      label: 'Start date *',
                      value: _start,
                      onPick: (DateTime d) => setState(() => _start = d),
                    ),
                  ),
                  const SizedBox(width: AppTheme.gapMd),
                  Expanded(
                    child: _DateField(
                      label: 'End date',
                      value: _end,
                      onPick: (DateTime d) => setState(() => _end = d),
                      onClear: () => setState(() => _end = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _vet,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Prescribed by',
                  hintText: 'Dr Anita Perera',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Give with food',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => Validators.notes(v, max: 300),
              ),
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.medicine),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save medicine'),
              ),
              const SizedBox(height: AppTheme.gapSm),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final DateTime now = DateTime.now();
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
        );
        // Stateless, so `context.mounted` is the available check. The picker
        // can outlive this field if the route is unwound while it is open.
        if (picked == null || !context.mounted) return;
        onPick(picked);
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value != null && onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear',
                )
              : null,
        ),
        child: Text(
          value == null
              ? 'Not set'
              : '${value!.day}/${value!.month}/${value!.year}',
          style: TextStyle(
            color: value == null
                ? AppColors.inkFaint
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
