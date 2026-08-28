import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';
import '../vet_repository.dart';

/// Chronological clinical record for one pet.
///
/// Entries are written whenever a clinically relevant event is recorded — a
/// completed vet visit, an owner observation — so this reads as one timeline
/// rather than requiring the reader to cross-reference six collections.
class MedicalHistoryView extends StatelessWidget {
  const MedicalHistoryView({
    super.key,
    required this.petId,
    required this.uid,
  });

  final String petId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final VetRepository repo = VetRepository(uid: uid);

    return StreamBuilder<List<MedicalHistoryEntry>>(
      stream: repo.watchMedicalHistory(petId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return ErrorView(message: snapshot.error.toString());
        }

        final List<MedicalHistoryEntry> entries =
            snapshot.data ?? const <MedicalHistoryEntry>[];

        return Stack(
          children: <Widget>[
            if (entries.isEmpty)
              EmptyState(
                icon: Icons.medical_information_outlined,
                accent: AppColors.vet,
                title: 'No medical records yet',
                message:
                    'Completed vet visits are filed here automatically. You can '
                    'also add your own health observations.',
                actionLabel: 'Add an observation',
                onAction: () => _addObservation(context, repo),
              )
            else
              ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gapLg,
                  AppTheme.gapLg,
                  AppTheme.gapLg,
                  96,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) => _TimelineEntry(
                  entry: entries[i],
                  isFirst: i == 0,
                  isLast: i == entries.length - 1,
                  onDelete: () async {
                    final bool ok = await confirmAction(
                      context,
                      title: 'Delete this record?',
                      message: '"${entries[i].title}" will be removed from the '
                          'medical history.',
                    );
                    if (!ok) return;
                    await repo.deleteMedicalHistory(petId, entries[i].id);
                    if (context.mounted) showAppSnack(context, 'Record deleted');
                  },
                ),
              ),
            Positioned(
              right: AppTheme.gapLg,
              bottom: AppTheme.gapLg,
              child: FloatingActionButton.extended(
                heroTag: 'add_history',
                onPressed: () => _addObservation(context, repo),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add record'),
                backgroundColor: AppColors.vet,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addObservation(BuildContext context, VetRepository repo) async {
    final TextEditingController title = TextEditingController();
    final TextEditingController description = TextEditingController();
    DateTime when = DateTime.now();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add health record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'Limping on left front paw',
                  ),
                ),
                const SizedBox(height: AppTheme.gapLg),
                TextField(
                  controller: description,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Details',
                    hintText: 'Noticed after the evening walk. Eating normally.',
                  ),
                ),
                const SizedBox(height: AppTheme.gapLg),
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: ctx,
                      initialDate: when,
                      firstDate: DateTime(DateTime.now().year - 20),
                      lastDate: DateTime.now(),
                    );
                    // The dialog can be dismissed while the picker is open —
                    // sign-out unwinds the whole stack — leaving this builder
                    // detached.
                    if (picked == null || !context.mounted) return;
                    setDialogState(() => when = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text('${when.day}/${when.month}/${when.year}'),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final String titleText = title.text.trim();
    final String descText = description.text.trim();
    title.dispose();
    description.dispose();

    if (saved != true || titleText.isEmpty) return;

    await repo.addMedicalHistory(
      petId,
      MedicalHistoryEntry(
        id: '',
        title: titleText,
        occurredAt: when,
        category: 'observation',
        description: descText.isEmpty ? null : descText,
        createdAt: DateTime.now(),
      ),
    );

    if (context.mounted) showAppSnack(context, 'Record added');
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.onDelete,
  });

  final MedicalHistoryEntry entry;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final CareType? type = entry.careType;
    final Color color = type?.color ?? AppColors.navy;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Timeline rail: a continuous line with a node per entry makes the
          // chronology readable at a glance.
          SizedBox(
            width: 34,
            child: Column(
              children: <Widget>[
                Container(
                  width: 2,
                  height: isFirst ? 8 : 14,
                  color: isFirst
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
              child: AppCard(
                accent: color,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 19),
                          tooltip: 'Delete record',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        AppPill(
                          label: type?.label ?? 'Observation',
                          color: color,
                          icon: type?.icon ?? Icons.visibility_outlined,
                        ),
                        const SizedBox(width: AppTheme.gapSm),
                        Text(
                          _date(entry.occurredAt),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if ((entry.description ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppTheme.gapSm),
                      Text(
                        entry.description!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (entry.veterinarianName != null) ...<Widget>[
                      const SizedBox(height: AppTheme.gapSm),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.person_outline_rounded,
                              size: 14, color: AppColors.inkFaint),
                          const SizedBox(width: 4),
                          Text(
                            entry.veterinarianName!,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// Standalone route wrapper, used when opening the medical record outside the
/// veterinary tab.
class MedicalHistoryScreen extends StatelessWidget {
  const MedicalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final String? uid = context.read<AuthController>().uid;

    return Scaffold(
      appBar: AppBar(title: Text('${care.pet.name}\'s medical record')),
      body: SafeArea(
        top: false,
        child: uid == null
            ? const SizedBox.shrink()
            : MedicalHistoryView(petId: care.pet.id, uid: uid),
      ),
    );
  }
}
