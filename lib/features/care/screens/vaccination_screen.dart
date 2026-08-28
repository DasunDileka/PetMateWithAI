import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/vaccination.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../care_controller.dart';

/// Vaccination record.
///
/// Every date here is entered by the owner from what their vet told them.
/// PetMate ships no vaccine catalogue and derives no schedule: inventing a due
/// date would be a clinical claim the app is explicitly not allowed to make.
class VaccinationScreen extends StatelessWidget {
  const VaccinationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final List<Vaccination> all = care.vaccinations;

    final List<Vaccination> upcoming = all
        .where((Vaccination v) => (v.daysUntilDue ?? -1) >= 0)
        .toList()
      ..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!));

    final List<Vaccination> overdue =
        all.where((Vaccination v) => v.isOverdue).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Vaccination')),
      body: SafeArea(
        top: false,
        child: all.isEmpty
            ? EmptyState(
                icon: CareType.vaccination.icon,
                accent: AppColors.vaccination,
                title: 'No vaccinations recorded',
                message:
                    'Add ${care.pet.name}\'s vaccination history from their '
                    'records or vaccination card to track what is due next.',
                actionLabel: 'Add vaccination',
                onAction: () => _openForm(context, care),
              )
            : ListView(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                children: <Widget>[
                  if (overdue.isNotEmpty) ...<Widget>[
                    InlineNotice(
                      message:
                          '${overdue.length} vaccination${overdue.length == 1 ? ' is' : 's are'} '
                          'past the due date recorded for ${care.pet.name}. '
                          'Check with your veterinarian.',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: AppTheme.gapLg),
                  ],

                  if (upcoming.isNotEmpty) ...<Widget>[
                    SectionHeader(
                      title: 'Coming up',
                      icon: Icons.event_available_rounded,
                    ),
                    ...upcoming.take(3).map((Vaccination v) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppTheme.gapMd),
                          child: AppCard(
                            accent: AppColors.vaccination,
                            child: Row(
                              children: <Widget>[
                                const CareIconTile(
                                  icon: Icons.event_rounded,
                                  color: AppColors.vaccination,
                                ),
                                const SizedBox(width: AppTheme.gapMd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(v.vaccineName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      Text(
                                        v.dueLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: AppTheme.gapXl),
                  ],

                  SectionHeader(
                    title: 'Vaccination history',
                    subtitle: '${all.length} recorded',
                    icon: Icons.history_rounded,
                  ),
                  ...all.map((Vaccination v) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                        child: _VaccinationCard(
                          vaccination: v,
                          care: care,
                          onEdit: () =>
                              _openForm(context, care, vaccination: v),
                        ),
                      )),
                  const SizedBox(height: 96),
                ],
              ),
      ),
      floatingActionButton: all.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context, care),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
              backgroundColor: AppColors.vaccination,
              foregroundColor: Colors.white,
            ),
    );
  }

  void _openForm(
    BuildContext context,
    CareController care, {
    Vaccination? vaccination,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _VaccinationForm(care: care, vaccination: vaccination),
      ),
    );
  }
}

class _VaccinationCard extends StatelessWidget {
  const _VaccinationCard({
    required this.vaccination,
    required this.care,
    required this.onEdit,
  });

  final Vaccination vaccination;
  final CareController care;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: vaccination.isOverdue ? AppColors.danger : AppColors.vaccination,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CareIconTile(
                icon: Icons.vaccines_rounded,
                color: AppColors.vaccination,
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(vaccination.vaccineName,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Given ${_date(vaccination.administeredAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Vaccination options',
                onSelected: (String v) async {
                  if (v == 'edit') {
                    onEdit();
                  } else if (v == 'delete') {
                    final bool ok = await confirmAction(
                      context,
                      title: 'Delete ${vaccination.vaccineName}?',
                      message: 'This vaccination record will be removed.',
                    );
                    if (!ok) return;
                    await care.repository.deleteVaccination(vaccination.id);
                    await NotificationService.instance
                        .cancelVaccination(care.pet.id, vaccination.id);
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
          Wrap(
            spacing: AppTheme.gapSm,
            runSpacing: AppTheme.gapSm,
            children: <Widget>[
              AppPill(
                label: vaccination.dueLabel,
                color: vaccination.isOverdue
                    ? AppColors.danger
                    : AppColors.vaccination,
                icon: Icons.schedule_rounded,
              ),
              if (vaccination.veterinarianName != null)
                AppPill(
                  label: vaccination.veterinarianName!,
                  color: AppColors.vet,
                  icon: Icons.person_outline_rounded,
                ),
              if (vaccination.batchNumber != null)
                AppPill(
                  label: 'Batch ${vaccination.batchNumber}',
                  color: AppColors.inkFaint,
                  icon: Icons.tag_rounded,
                ),
            ],
          ),
          if ((vaccination.notes ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Text(vaccination.notes!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _VaccinationForm extends StatefulWidget {
  const _VaccinationForm({required this.care, this.vaccination});

  final CareController care;
  final Vaccination? vaccination;

  @override
  State<_VaccinationForm> createState() => _VaccinationFormState();
}

class _VaccinationFormState extends State<_VaccinationForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.vaccination?.vaccineName ?? '');
  late final TextEditingController _vet =
      TextEditingController(text: widget.vaccination?.veterinarianName ?? '');
  late final TextEditingController _batch =
      TextEditingController(text: widget.vaccination?.batchNumber ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.vaccination?.notes ?? '');

  late DateTime _given = widget.vaccination?.administeredAt ?? DateTime.now();
  late DateTime? _nextDue = widget.vaccination?.nextDueAt;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _vet.dispose();
    _batch.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final Vaccination vaccination = Vaccination(
      id: widget.vaccination?.id ?? '',
      vaccineName: _name.text.trim(),
      administeredAt: _given,
      nextDueAt: _nextDue,
      veterinarianName: _vet.text.trim().isEmpty ? null : _vet.text.trim(),
      batchNumber: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: widget.vaccination?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.vaccination == null) {
        final String id =
            await widget.care.repository.addVaccination(vaccination);
        await NotificationService.instance.scheduleVaccination(
          pet: widget.care.pet,
          vaccination: Vaccination(
            id: id,
            vaccineName: vaccination.vaccineName,
            administeredAt: vaccination.administeredAt,
            nextDueAt: vaccination.nextDueAt,
            veterinarianName: vaccination.veterinarianName,
            batchNumber: vaccination.batchNumber,
            notes: vaccination.notes,
            createdAt: vaccination.createdAt,
          ),
        );
      } else {
        await widget.care.repository.updateVaccination(vaccination);
        await NotificationService.instance.scheduleVaccination(
          pet: widget.care.pet,
          vaccination: vaccination,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Vaccination saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the vaccination.', isError: true);
    }
  }

  Future<void> _pick({required bool isGiven}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isGiven ? _given : (_nextDue ?? now),
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 10),
      helpText: isGiven ? 'Date administered' : 'Next dose due',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isGiven) {
        _given = picked;
      } else {
        _nextDue = picked;
      }
    });
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
                widget.vaccination == null
                    ? 'Add vaccination'
                    : 'Edit vaccination',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.gapXs),
              Text(
                'Enter the details from your vaccination record. The next due '
                'date should be the one your veterinarian gave you.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Vaccine name *',
                  hintText: 'Rabies',
                  prefixIcon: Icon(Icons.vaccines_outlined),
                ),
                validator: (v) => Validators.required(v, field: 'Vaccine name'),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: () => _pick(isGiven: true),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date administered *',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  child: Text('${_given.day}/${_given.month}/${_given.year}'),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: () => _pick(isGiven: false),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Next dose due',
                    prefixIcon: const Icon(Icons.event_repeat_rounded),
                    suffixIcon: _nextDue == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _nextDue = null),
                            tooltip: 'Clear',
                          ),
                  ),
                  child: Text(
                    _nextDue == null
                        ? 'Not set'
                        : '${_nextDue!.day}/${_nextDue!.month}/${_nextDue!.year}',
                    style: TextStyle(
                      color: _nextDue == null
                          ? AppColors.inkFaint
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _vet,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Administered by',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _batch,
                decoration: const InputDecoration(
                  labelText: 'Batch number',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => Validators.notes(v, max: 300),
              ),
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.vaccination),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save vaccination'),
              ),
              const SizedBox(height: AppTheme.gapSm),
            ],
          ),
        ),
      ),
    );
  }
}
