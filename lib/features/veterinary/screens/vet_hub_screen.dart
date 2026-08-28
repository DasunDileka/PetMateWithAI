import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/veterinarian.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';
import '../vet_repository.dart';
import 'appointment_form_screen.dart';
import 'medical_history_screen.dart';
import 'vet_form_screen.dart';
import 'vet_map_screen.dart';

/// Veterinary hub: saved clinics, appointments and the medical record.
///
/// Three related but distinct datasets behind one tab, so the bottom navigation
/// stays at five destinations as the brief recommends.
class VetHubScreen extends StatefulWidget {
  const VetHubScreen({super.key});

  @override
  State<VetHubScreen> createState() => _VetHubScreenState();
}

class _VetHubScreenState extends State<VetHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Veterinary'),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VetMapScreen()),
            ),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Find clinics near me',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Tab>[
            Tab(text: 'Appointments'),
            Tab(text: 'Vets'),
            Tab(text: 'Medical'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: <Widget>[
            _AppointmentsTab(care: care, uid: uid),
            _VetsTab(uid: uid),
            MedicalHistoryView(petId: care.pet.id, uid: uid),
          ],
        ),
      ),
    );
  }
}

// ============================================================ appointments

class _AppointmentsTab extends StatelessWidget {
  const _AppointmentsTab({required this.care, required this.uid});

  final CareController care;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final List<Appointment> all = care.appointments;

    final List<Appointment> upcoming = all
        .where((Appointment a) => a.status == AppointmentStatus.upcoming)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final List<Appointment> past = all
        .where((Appointment a) => a.status != AppointmentStatus.upcoming)
        .toList();

    return Stack(
      children: <Widget>[
        if (all.isEmpty)
          EmptyState(
            icon: CareType.appointment.icon,
            accent: AppColors.vet,
            title: 'No appointments',
            message:
                'No upcoming veterinary appointments for ${care.pet.name}. '
                'Create one to get a reminder the day before.',
            actionLabel: 'Create appointment',
            onAction: () => _open(context, care),
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapLg,
              AppTheme.gapLg,
              AppTheme.gapLg,
              96,
            ),
            children: <Widget>[
              if (upcoming.isNotEmpty) ...<Widget>[
                SectionHeader(
                  title: 'Upcoming',
                  subtitle: '${upcoming.length} scheduled',
                  icon: Icons.event_rounded,
                ),
                ...upcoming.map((Appointment a) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                      child: _AppointmentCard(
                        appointment: a,
                        care: care,
                        uid: uid,
                      ),
                    )),
                const SizedBox(height: AppTheme.gapXl),
              ],
              if (past.isNotEmpty) ...<Widget>[
                SectionHeader(
                  title: 'Past appointments',
                  icon: Icons.history_rounded,
                ),
                ...past.map((Appointment a) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
                      child: _AppointmentCard(
                        appointment: a,
                        care: care,
                        uid: uid,
                      ),
                    )),
              ],
            ],
          ),
        Positioned(
          right: AppTheme.gapLg,
          bottom: AppTheme.gapLg,
          child: FloatingActionButton.extended(
            heroTag: 'add_appointment',
            onPressed: () => _open(context, care),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New'),
            backgroundColor: AppColors.vet,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, CareController care, {Appointment? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentFormScreen(care: care, appointment: existing),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.care,
    required this.uid,
  });

  final Appointment appointment;
  final CareController care;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final VetRepository repo = VetRepository(uid: uid);

    return AppCard(
      accent: appointment.status.color,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AppointmentFormScreen(care: care, appointment: appointment),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CareIconTile(
                icon: Icons.local_hospital_rounded,
                color: AppColors.vet,
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(appointment.reason,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      appointment.whenLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AppPill(
                label: appointment.status.label,
                color: appointment.status.color,
              ),
            ],
          ),
          if (appointment.veterinarianName != null ||
              appointment.clinicName != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Row(
              children: <Widget>[
                const Icon(Icons.person_outline_rounded,
                    size: 15, color: AppColors.inkFaint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    <String>[
                      if (appointment.veterinarianName != null)
                        appointment.veterinarianName!,
                      if (appointment.clinicName != null) appointment.clinicName!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (appointment.isAwaitingOutcome) ...<Widget>[
            const Divider(height: AppTheme.gapXl),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'This appointment has passed. Record what happened?',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: () => _recordOutcome(context, repo),
                  child: const Text('Record'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _recordOutcome(BuildContext context, VetRepository repo) async {
    final TextEditingController controller = TextEditingController();

    final String? outcome = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Visit outcome'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Record what the veterinarian said. This is added to the medical '
              'history.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppTheme.gapLg),
            TextField(
              controller: controller,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Healthy. Weight stable. Next check in 6 months.',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (outcome == null || outcome.isEmpty) return;

    await repo.completeAppointment(
      petId: care.pet.id,
      appointment: appointment,
      outcome: outcome,
    );

    if (context.mounted) {
      showAppSnack(context, 'Visit recorded in medical history');
    }
  }
}

// =================================================================== vets

class _VetsTab extends StatelessWidget {
  const _VetsTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final VetRepository repo = VetRepository(uid: uid);

    return StreamBuilder<List<Veterinarian>>(
      stream: repo.watchVeterinarians(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return ErrorView(message: snapshot.error.toString());
        }

        final List<Veterinarian> vets = snapshot.data ?? const <Veterinarian>[];

        return Stack(
          children: <Widget>[
            if (vets.isEmpty)
              EmptyState(
                icon: Icons.medical_information_outlined,
                accent: AppColors.vet,
                title: 'No veterinarians saved',
                message:
                    'Save your vet\'s contact details so you can reach them '
                    'quickly and attach them to appointments.',
                actionLabel: 'Add veterinarian',
                onAction: () => _open(context),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gapLg,
                  AppTheme.gapLg,
                  AppTheme.gapLg,
                  96,
                ),
                itemCount: vets.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppTheme.gapMd),
                itemBuilder: (context, i) => _VetCard(
                  vet: vets[i],
                  repo: repo,
                  onEdit: () => _open(context, vet: vets[i]),
                ),
              ),
            Positioned(
              right: AppTheme.gapLg,
              bottom: AppTheme.gapLg,
              child: FloatingActionButton.extended(
                heroTag: 'add_vet',
                onPressed: () => _open(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add vet'),
                backgroundColor: AppColors.vet,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, {Veterinarian? vet}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VetFormScreen(vet: vet)),
    );
  }
}

class _VetCard extends StatelessWidget {
  const _VetCard({
    required this.vet,
    required this.repo,
    required this.onEdit,
  });

  final Veterinarian vet;
  final VetRepository repo;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: AppColors.vet,
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.vet.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  vet.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.vet,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(vet.doctorName,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (vet.clinicName != null)
                      Text(
                        vet.clinicName!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Vet options',
                onSelected: (String v) async {
                  if (v == 'edit') {
                    onEdit();
                  } else if (v == 'delete') {
                    final bool ok = await confirmAction(
                      context,
                      title: 'Delete ${vet.doctorName}?',
                      message:
                          'The contact will be removed. Appointments that '
                          'reference them keep the recorded name.',
                    );
                    if (!ok) return;
                    await repo.deleteVeterinarian(vet.id);
                    if (context.mounted) showAppSnack(context, 'Vet deleted');
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
              if (vet.specialisation != null)
                AppPill(
                  label: vet.specialisation!,
                  color: AppColors.vet,
                  icon: Icons.workspace_premium_outlined,
                ),
              if (vet.phone != null)
                AppPill(
                  label: vet.phone!,
                  color: AppColors.info,
                  icon: Icons.phone_outlined,
                ),
              if (vet.hasLocation)
                const AppPill(
                  label: 'On map',
                  color: AppColors.leaf,
                  icon: Icons.place_outlined,
                ),
            ],
          ),
          if (vet.address != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Text(
              vet.address!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
