import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/veterinarian.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../vet_repository.dart';

/// Add or edit a saved veterinarian.
class VetFormScreen extends StatefulWidget {
  const VetFormScreen({super.key, this.vet});

  final Veterinarian? vet;

  bool get isEditing => vet != null;

  @override
  State<VetFormScreen> createState() => _VetFormScreenState();
}

class _VetFormScreenState extends State<VetFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final LocationService _location = const LocationService();

  late final TextEditingController _doctor =
      TextEditingController(text: widget.vet?.doctorName ?? '');
  late final TextEditingController _clinic =
      TextEditingController(text: widget.vet?.clinicName ?? '');
  late final TextEditingController _speciality =
      TextEditingController(text: widget.vet?.specialisation ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.vet?.phone ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.vet?.email ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.vet?.address ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.vet?.notes ?? '');

  late double? _lat = widget.vet?.latitude;
  late double? _lng = widget.vet?.longitude;

  bool _saving = false;
  bool _locating = false;

  @override
  void dispose() {
    _doctor.dispose();
    _clinic.dispose();
    _speciality.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locating = false;
      });
      showAppSnack(context, 'Clinic location saved');
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      showAppSnack(context, e.message, isError: true);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return;

    setState(() => _saving = true);

    final Veterinarian vet = Veterinarian(
      id: widget.vet?.id ?? '',
      doctorName: _doctor.text.trim(),
      clinicName: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
      specialisation:
          _speciality.text.trim().isEmpty ? null : _speciality.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      latitude: _lat,
      longitude: _lng,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      petIds: widget.vet?.petIds ?? const <String>[],
      createdAt: widget.vet?.createdAt ?? DateTime.now(),
    );

    try {
      final VetRepository repo = VetRepository(uid: uid);
      if (widget.isEditing) {
        await repo.updateVeterinarian(vet);
      } else {
        await repo.addVeterinarian(vet);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Veterinarian saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save. Please try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit veterinarian' : 'Add veterinarian'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.gapLg),
            children: <Widget>[
              TextFormField(
                controller: _doctor,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Doctor name *',
                  hintText: 'Dr Anita Perera',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => Validators.required(v, field: 'Doctor name'),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _clinic,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Clinic name',
                  hintText: 'Colombo Pet Clinic',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _speciality,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Specialisation',
                  hintText: 'Small animal medicine',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => Validators.phone(v),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: Validators.optionalEmail,
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _address,
                maxLines: 2,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.gapMd),

              AppCard(
                child: Row(
                  children: <Widget>[
                    const CareIconTile(
                      icon: Icons.my_location_rounded,
                      color: AppColors.leaf,
                      size: 36,
                    ),
                    const SizedBox(width: AppTheme.gapMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Clinic location',
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            _lat == null || _lng == null
                                ? 'Not saved — plot this clinic on the map'
                                : '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_locating)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _useCurrentLocation,
                        child: Text(_lat == null ? 'Use current' : 'Update'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),

              TextFormField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Open Mon–Sat, emergency line after 8pm',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => Validators.notes(v),
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
                    : Text(widget.isEditing ? 'Save changes' : 'Add veterinarian'),
              ),
              const SizedBox(height: AppTheme.gapXl),
            ],
          ),
        ),
      ),
    );
  }
}
