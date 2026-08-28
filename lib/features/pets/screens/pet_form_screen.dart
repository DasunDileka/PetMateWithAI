import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/services/photo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/pet.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../pet_controller.dart';

/// Add or edit a pet.
///
/// One screen serves both cases: passing [pet] switches it to edit mode. The
/// alternative — two near-identical forms — is exactly the kind of duplication
/// that drifts out of sync as fields are added.
class PetFormScreen extends StatefulWidget {
  const PetFormScreen({super.key, this.pet});

  final Pet? pet;

  bool get isEditing => pet != null;

  @override
  State<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends State<PetFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final PhotoService _photos = PhotoService();

  late final TextEditingController _name =
      TextEditingController(text: widget.pet?.name ?? '');
  late final TextEditingController _breed =
      TextEditingController(text: widget.pet?.breed ?? '');
  late final TextEditingController _weight = TextEditingController(
    text: (widget.pet?.weightKg ?? 0) > 0
        ? _trim(widget.pet!.weightKg)
        : '',
  );
  late final TextEditingController _notes =
      TextEditingController(text: widget.pet?.notes ?? '');

  late PetSpecies _species = widget.pet?.species ?? PetSpecies.dog;
  late PetGender _gender = widget.pet?.gender ?? PetGender.unknown;
  late DateTime? _dob = widget.pet?.dateOfBirth;
  late String? _photoUrl = widget.pet?.photoUrl;

  bool _saving = false;
  bool _uploadingPhoto = false;

  static String _trim(double v) {
    final String s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 2, now.month, now.day),
      firstDate: DateTime(now.year - 40),
      // A pet cannot be born in the future.
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked == null || !mounted) return;
    setState(() => _dob = picked);
  }

  Future<void> _pickPhoto() async {
    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppTheme.gapSm),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            if (_photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger),
                title: const Text('Remove photo',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _photoUrl = null);
                },
              ),
            const SizedBox(height: AppTheme.gapSm),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    // The photo needs a stable id to key its storage path. For a new pet the
    // document does not exist yet, so a temporary id is used and the file is
    // re-pathed on save.
    final String petId = widget.pet?.id ?? 'draft_${DateTime.now().millisecondsSinceEpoch}';

    setState(() => _uploadingPhoto = true);

    final PhotoResult result = await _photos.pickAndUploadPetPhoto(
      uid: uid,
      petId: petId,
      source: source,
    );

    if (!mounted) return;
    setState(() => _uploadingPhoto = false);

    if (result.isSuccess) {
      setState(() => _photoUrl = result.downloadUrl);
    } else if (result.error != null) {
      showAppSnack(context, result.error!, isError: true);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final PetController pets = context.read<PetController>();
    final AuthController auth = context.read<AuthController>();

    setState(() => _saving = true);

    // Clearing the field is not enough on its own: the object stays in Cloud
    // Storage, still billable and still reachable by its download URL. Removing
    // a photo has to remove the file too.
    if (widget.isEditing &&
        (widget.pet?.photoUrl ?? '').isNotEmpty &&
        _photoUrl == null) {
      final String? ownerId = auth.uid;
      if (ownerId != null) {
        await _photos.deletePetPhoto(uid: ownerId, petId: widget.pet!.id);
      }
    }

    final double weight = double.tryParse(_weight.text.trim()) ?? 0;

    final Pet pet = Pet(
      id: widget.pet?.id ?? '',
      name: _name.text.trim(),
      species: _species,
      breed: _breed.text.trim().isEmpty ? null : _breed.text.trim(),
      gender: _gender,
      dateOfBirth: _dob,
      weightKg: weight,
      photoUrl: _photoUrl,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      primaryVetId: widget.pet?.primaryVetId,
      createdAt: widget.pet?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    bool ok;
    if (widget.isEditing) {
      ok = await pets.updatePet(pet);
    } else {
      final String? id = await pets.addPet(pet);
      ok = id != null;
      if (ok) await auth.setActivePet(id);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop();
      showAppSnack(
        context,
        widget.isEditing
            ? '${pet.name}\'s details were updated'
            : '${pet.name} was added',
      );
    } else {
      showAppSnack(context, pets.error ?? 'Could not save. Please try again.',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit pet' : 'Add a pet'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.gapLg),
            children: <Widget>[
              Center(
                child: Stack(
                  children: <Widget>[
                    PetAvatar(
                      photoUrl: _photoUrl,
                      fallbackEmoji: _species.emoji,
                      size: 104,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.navy,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploadingPhoto ? null : _pickPhoto,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: _uploadingPhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_rounded,
                                    size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.gapXl),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Pet name *',
                  hintText: 'Bruno',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: Validators.petName,
              ),
              const SizedBox(height: AppTheme.gapLg),

              const _FieldLabel('Species *'),
              Wrap(
                spacing: AppTheme.gapSm,
                runSpacing: AppTheme.gapSm,
                children: PetSpecies.values.map((PetSpecies s) {
                  return ChoiceChip(
                    label: Text('${s.emoji}  ${s.label}'),
                    selected: _species == s,
                    onSelected: (_) => setState(() => _species = s),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _breed,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Breed',
                  hintText: 'Labrador Retriever',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              const _FieldLabel('Sex'),
              Wrap(
                spacing: AppTheme.gapSm,
                children: PetGender.values.map((PetGender g) {
                  return ChoiceChip(
                    avatar: Icon(g.icon, size: 16),
                    label: Text(g.label),
                    selected: _gender == g,
                    onSelected: (_) => setState(() => _gender = g),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTheme.gapLg),

              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of birth',
                    prefixIcon: Icon(Icons.cake_outlined),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _dob == null
                              ? 'Not set'
                              : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                          style: TextStyle(
                            color: _dob == null
                                ? AppColors.inkFaint
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (_dob != null)
                        Text(
                          Pet(
                            id: '',
                            name: '',
                            species: _species,
                            dateOfBirth: _dob,
                            createdAt: DateTime.now(),
                          ).ageLabel,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      const SizedBox(width: AppTheme.gapSm),
                      const Icon(Icons.calendar_today_rounded, size: 17),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  hintText: '18.5',
                  prefixIcon: Icon(Icons.monitor_weight_outlined),
                  suffixText: 'kg',
                ),
                validator: (v) => Validators.weight(v, optional: true),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _notes,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Allergies, temperament, anything worth remembering',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 44),
                    child: Icon(Icons.notes_rounded),
                  ),
                ),
                validator: (v) => Validators.notes(v),
              ),
              const SizedBox(height: AppTheme.gapLg),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isEditing ? 'Save changes' : 'Add pet'),
              ),
              const SizedBox(height: AppTheme.gapXl),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapSm, left: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
