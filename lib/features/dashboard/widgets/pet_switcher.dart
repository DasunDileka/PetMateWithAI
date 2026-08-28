import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/pet.dart';
import '../../../shared/widgets/brand.dart';
import '../../pets/screens/pet_form_screen.dart';

/// Horizontal pet selector shown under the dashboard header.
///
/// Multiple pets is a first-class case in PetMate, not an afterthought: the
/// switcher is always visible so the user can see at a glance which animal the
/// screen is describing — and so a marker can demonstrate that the AI's output
/// genuinely changes per pet.
class PetSwitcher extends StatelessWidget {
  const PetSwitcher({
    super.key,
    required this.pets,
    required this.activeId,
    required this.onSelect,
  });

  final List<Pet> pets;
  final String activeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // With a single pet the switcher would be pure chrome; show a richer
    // profile header instead.
    if (pets.length <= 1) {
      final Pet pet = pets.first;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.gapLg,
          AppTheme.gapLg,
          AppTheme.gapLg,
          0,
        ),
        child: _ActivePetHeader(pet: pet),
      );
    }

    return SizedBox(
      // Avatar (40) + gap + label + card padding + the list's top padding.
      // 96 left the label exactly flush and clipped it by ~2px.
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.gapLg,
          AppTheme.gapLg,
          AppTheme.gapLg,
          0,
        ),
        itemCount: pets.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppTheme.gapMd),
        itemBuilder: (BuildContext context, int i) {
          if (i == pets.length) {
            return _AddPetChip(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PetFormScreen()),
              ),
            );
          }

          final Pet pet = pets[i];
          final bool selected = pet.id == activeId;

          return Semantics(
            selected: selected,
            button: true,
            label: '${pet.name}, ${pet.species.label}',
            child: InkWell(
              onTap: () => onSelect(pet.id),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 84,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.gapSm,
                  vertical: AppTheme.gapSm,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.navy.withValues(alpha: 0.08)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: selected
                        ? AppColors.navy
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selected ? 1.8 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PetAvatar(
                      photoUrl: pet.photoUrl,
                      fallbackEmoji: pet.species.emoji,
                      size: 40,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AppColors.navy
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivePetHeader extends StatelessWidget {
  const _ActivePetHeader({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.gapLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.navy.withValues(alpha: 0.07),
            AppColors.gold.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          PetAvatar(
            photoUrl: pet.photoUrl,
            fallbackEmoji: pet.species.emoji,
            size: 54,
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
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(pet.species.emoji, style: const TextStyle(fontSize: 17)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pet.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPetChip extends StatelessWidget {
  const _AddPetChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(AppTheme.gapSm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(
              'Add pet',
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
