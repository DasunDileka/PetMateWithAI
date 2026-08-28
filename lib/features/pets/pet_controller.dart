import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/models/pet.dart';
import 'pet_repository.dart';

/// Owns the user's pet list and which pet is currently selected.
///
/// The selected pet is the app's central piece of shared state: the dashboard,
/// every care screen, the calendar and the AI assistant all read from it, so it
/// lives here rather than being threaded through navigation arguments.
class PetController extends ChangeNotifier {
  PetController({required this.uid, PetRepository? repository})
      : _repo = repository ?? PetRepository(uid) {
    _subscribe();
  }

  final String uid;
  final PetRepository _repo;

  StreamSubscription<List<Pet>>? _sub;

  List<Pet> _pets = const <Pet>[];
  String? _activePetId;
  bool _loading = true;
  String? _error;

  List<Pet> get pets => _pets;
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => !_loading && _pets.isEmpty;
  bool get hasPets => _pets.isNotEmpty;

  Pet? get activePet {
    if (_pets.isEmpty) return null;
    for (final Pet p in _pets) {
      if (p.id == _activePetId) return p;
    }
    return _pets.first;
  }

  String? get activePetId => activePet?.id;

  void _subscribe() {
    _sub?.cancel();
    _sub = _repo.watchPets().listen(
      (List<Pet> pets) {
        _pets = pets;
        _loading = false;
        _error = null;

        // Keep the selection valid when the selected pet is deleted, including
        // from another device.
        if (_activePetId != null && !pets.any((p) => p.id == _activePetId)) {
          _activePetId = pets.isEmpty ? null : pets.first.id;
        }

        notifyListeners();
      },
      onError: (Object e) {
        _loading = false;
        _error = e is DataFailure
            ? e.message
            : 'Could not load your pets. Please try again.';
        if (kDebugMode) debugPrint('pet stream error: $e');
        notifyListeners();
      },
    );
  }

  /// Applies the pet remembered on the user's profile, without clobbering a
  /// selection the user has already made this session.
  void restoreActivePet(String? petId) {
    if (petId == null || _activePetId != null) return;
    if (_pets.isEmpty || _pets.any((p) => p.id == petId)) {
      _activePetId = petId;
      notifyListeners();
    }
  }

  void selectPet(String petId) {
    if (_activePetId == petId) return;
    _activePetId = petId;
    notifyListeners();
  }

  // ------------------------------------------------------------------ CRUD

  Future<String?> addPet(Pet pet) async {
    try {
      final String id = await _repo.addPet(pet);
      // Select the pet that was just created — it is almost certainly the one
      // the user wants to work with next.
      _activePetId = id;
      notifyListeners();
      return id;
    } on DataFailure catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updatePet(Pet pet) async {
    try {
      await _repo.updatePet(pet);
      return true;
    } on DataFailure catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletePet(String petId) async {
    try {
      await _repo.deletePet(petId);
      if (_activePetId == petId) _activePetId = null;
      return true;
    } on DataFailure catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
