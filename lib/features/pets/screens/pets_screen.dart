import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pet.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../pet_controller.dart';
import 'pet_form_screen.dart';

/// Manages the user's pets: view, select, edit and delete.
class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PetController pets = context.watch<PetController>();
    final AuthController auth = context.read<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pets'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _openForm(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add a pet',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: pets.loading
            ? const LoadingView()
            : pets.pets.isEmpty
                ? EmptyState(
                    icon: Icons.pets_rounded,
                    title: 'No pets yet',
                    message:
                        'You haven\'t added a pet yet. Add your first pet to '
                        'get started with care tracking and AI insights.',
                    actionLabel: 'Add your first pet',
                    onAction: () => _openForm(context),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppTheme.gapLg),
                    itemCount: pets.pets.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTheme.gapMd),
                    itemBuilder: (BuildContext context, int i) {
                      final Pet pet = pets.pets[i];
                      final bool active = pet.id == pets.activePetId;

                      return _PetCard(
                        pet: pet,
                        isActive: active,
                        onSelect: () {
                          pets.selectPet(pet.id);
                          auth.setActivePet(pet.id);
                          showAppSnack(context, '${pet.name} is now selected');
                        },
                        onEdit: () => _openForm(context, pet: pet),
                        onDelete: () => _confirmDelete(context, pets, pet),
                      );
                    },
                  ),
      ),
      floatingActionButton: pets.pets.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add pet'),
            ),
    );
  }

  void _openForm(BuildContext context, {Pet? pet}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PetFormScreen(pet: pet)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PetController pets,
    Pet pet,
  ) async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Delete ${pet.name}?',
      message:
          'This permanently removes ${pet.name} and every care record, '
          'appointment and medical history entry belonging to them. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
    );

    if (!confirmed || !context.mounted) return;

    // Deleting a pet clears its subcollections in batches, so show progress.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: AppTheme.gapLg),
            Expanded(child: Text('Deleting records…')),
          ],
        ),
      ),
    );

    final bool ok = await pets.deletePet(pet.id);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress dialog

    showAppSnack(
      context,
      ok ? '${pet.name} was deleted' : (pets.error ?? 'Could not delete pet'),
      isError: !ok,
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({
    required this.pet,
    required this.isActive,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final Pet pet;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: isActive ? null : onSelect,
      borderColor: isActive ? AppColors.navy : null,
      child: Row(
        children: <Widget>[
          PetAvatar(
            photoUrl: pet.photoUrl,
            fallbackEmoji: pet.species.emoji,
            size: 60,
          ),
          const SizedBox(width: AppTheme.gapLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        pet.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive) ...<Widget>[
                      const SizedBox(width: AppTheme.gapSm),
                      const AppPill(label: 'Selected', color: AppColors.navy),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  pet.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((pet.notes ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    pet.notes!.trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Pet options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (String value) {
              switch (value) {
                case 'select':
                  onSelect();
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              if (!isActive)
                const PopupMenuItem<String>(
                  value: 'select',
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline_rounded),
                    title: Text('Set as active'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                  title: Text('Delete', style: TextStyle(color: AppColors.danger)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
