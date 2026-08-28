import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/veterinarian.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../ai/screens/vet_summary_screen.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';
import '../vet_repository.dart';

/// Create or edit a veterinary appointment.
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({
    super.key,
    required this.care,
    this.appointment,
  });

  final CareController care;
  final Appointment? appointment;

  bool get isEditing => appointment != null;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _reason =
      TextEditingController(text: widget.appointment?.reason ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.appointment?.notes ?? '');

  late DateTime _when = widget.appointment?.scheduledAt ??
      DateTime.now().add(const Duration(days: 1));
  late AppointmentStatus _status =
      widget.appointment?.status ?? AppointmentStatus.upcoming;

  Veterinarian? _vet;
  String? _vetIdFromRecord;
  bool _saving = false;

  static const List<String> _reasonPresets = <String>[
    'Routine check-up',
    'Vaccination',
    'Follow-up',
    'Dental check',
    'Skin condition',
    'Injury',
  ];

  @override
  void initState() {
    super.initState();
    _vetIdFromRecord = widget.appointment?.veterinarianId;
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      helpText: 'Appointment date',
    );
    if (date == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
      helpText: 'Appointment time',
    );
    if (!mounted) return;

    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return;

    setState(() => _saving = true);

    final Appointment appointment = Appointment(
      id: widget.appointment?.id ?? '',
      scheduledAt: _when,
      reason: _reason.text.trim(),
      veterinarianId: _vet?.id ?? _vetIdFromRecord,
      veterinarianName: _vet?.doctorName ?? widget.appointment?.veterinarianName,
      clinicName: _vet?.clinicName ?? widget.appointment?.clinicName,
      status: _status,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      outcome: widget.appointment?.outcome,
      createdAt: widget.appointment?.createdAt ?? DateTime.now(),
    );

    try {
      final VetRepository repo = VetRepository(uid: uid);

      if (widget.isEditing) {
        await repo.updateAppointment(widget.care.pet.id, appointment);
        await NotificationService.instance.scheduleAppointment(
          pet: widget.care.pet,
          appointment: appointment,
        );
      } else {
        final String id =
            await repo.addAppointment(widget.care.pet.id, appointment);
        await NotificationService.instance.scheduleAppointment(
          pet: widget.care.pet,
          appointment: Appointment(
            id: id,
            scheduledAt: appointment.scheduledAt,
            reason: appointment.reason,
            veterinarianId: appointment.veterinarianId,
            veterinarianName: appointment.veterinarianName,
            clinicName: appointment.clinicName,
            status: appointment.status,
            notes: appointment.notes,
            createdAt: appointment.createdAt,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Appointment saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the appointment.', isError: true);
    }
  }

  Future<void> _delete() async {
    final String? uid = context.read<AuthController>().uid;
    if (uid == null || widget.appointment == null) return;

    final bool ok = await confirmAction(
      context,
      title: 'Delete appointment?',
      message: 'This appointment and its reminder will be removed.',
    );
    if (!ok || !mounted) return;

    await VetRepository(uid: uid)
        .deleteAppointment(widget.care.pet.id, widget.appointment!.id);
    await NotificationService.instance
        .cancelAppointment(widget.care.pet.id, widget.appointment!.id);

    if (!mounted) return;
    Navigator.of(context).pop();
    showAppSnack(context, 'Appointment deleted');
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = context.read<AuthController>().uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit appointment' : 'New appointment'),
        actions: <Widget>[
          if (widget.isEditing)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete appointment',
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.gapLg),
            children: <Widget>[
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
                          Text('For ${widget.care.pet.name}',
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            widget.care.pet.subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason for visit *',
                  prefixIcon: Icon(Icons.assignment_outlined),
                ),
                validator: (v) => Validators.required(v, field: 'Reason'),
              ),
              const SizedBox(height: AppTheme.gapSm),
              Wrap(
                spacing: AppTheme.gapSm,
                runSpacing: AppTheme.gapSm,
                children: _reasonPresets
                    .map((String r) => ActionChip(
                          label: Text(r),
                          onPressed: () => setState(() => _reason.text = r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: _pickWhen,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date and time *',
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

              if (uid != null)
                StreamBuilder<List<Veterinarian>>(
                  stream: VetRepository(uid: uid).watchVeterinarians(),
                  builder: (context, snapshot) {
                    final List<Veterinarian> vets =
                        snapshot.data ?? const <Veterinarian>[];

                    // Resolve the stored vet id to an object once the list loads.
                    if (_vet == null && _vetIdFromRecord != null) {
                      for (final Veterinarian v in vets) {
                        if (v.id == _vetIdFromRecord) {
                          _vet = v;
                          break;
                        }
                      }
                    }

                    if (vets.isEmpty) {
                      return InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Veterinarian',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        child: Text(
                          'No saved vets — add one from the Vets tab',
                          style: TextStyle(
                            color: AppColors.inkFaint,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }

                    return DropdownButtonFormField<Veterinarian>(
                      initialValue: _vet,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Veterinarian',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      items: vets
                          .map((Veterinarian v) => DropdownMenuItem<Veterinarian>(
                                value: v,
                                child: Text(
                                  v.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (Veterinarian? v) => setState(() => _vet = v),
                    );
                  },
                ),
              const SizedBox(height: AppTheme.gapLg),

              if (widget.isEditing) ...<Widget>[
                DropdownButtonFormField<AppointmentStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: AppointmentStatus.values
                      .map((AppointmentStatus s) =>
                          DropdownMenuItem<AppointmentStatus>(
                            value: s,
                            child: Text(s.label),
                          ))
                      .toList(),
                  onChanged: (AppointmentStatus? s) =>
                      setState(() => _status = s ?? AppointmentStatus.upcoming),
                ),
                const SizedBox(height: AppTheme.gapLg),
              ],

              TextFormField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Questions to ask, symptoms to mention',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => Validators.notes(v),
              ),
              const SizedBox(height: AppTheme.gapLg),

              // Preparing for a visit is where the AI summary is most useful,
              // so it is offered right here rather than buried in the AI tab.
              AppCard(
                accent: AppColors.navy,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VetSummaryScreen(),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const CareIconTile(
                      icon: Icons.auto_awesome_rounded,
                      color: AppColors.navy,
                      size: 36,
                    ),
                    const SizedBox(width: AppTheme.gapMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('AI visit summary',
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            'Generate a factual summary of recent care to show '
                            'the vet',
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
              const SizedBox(height: AppTheme.gapXl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.vet),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(widget.isEditing
                        ? 'Save changes'
                        : 'Create appointment'),
              ),
              const SizedBox(height: AppTheme.gapXl),
            ],
          ),
        ),
      ),
    );
  }
}
