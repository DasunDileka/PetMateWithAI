import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/firestore_refs.dart';
import '../../shared/models/pet.dart';

/// Raised by any repository with user-safe copy.
class DataFailure implements Exception {
  const DataFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;

  /// Maps a Firestore exception onto neutral wording. Raw Firebase messages
  /// name internal rule paths, which should never reach the screen.
  factory DataFailure.from(Object error) {
    if (error is DataFailure) return error;
    if (error is FirebaseException) {
      final String message = switch (error.code) {
        'permission-denied' =>
          'You do not have permission to access this data.',
        'unavailable' || 'network-request-failed' =>
          'No connection to the server. Your changes will sync when you are back online.',
        'deadline-exceeded' => 'That took too long. Please try again.',
        'not-found' => 'That record no longer exists.',
        'already-exists' => 'That record already exists.',
        'resource-exhausted' => 'Service limit reached. Please try again later.',
        'failed-precondition' =>
          'The app needs a database index that has not finished building yet.',
        _ => 'Something went wrong saving your data.',
      };
      if (kDebugMode) debugPrint('Firestore error: ${error.code}');
      return DataFailure(message, code: error.code);
    }
    if (kDebugMode) debugPrint('Unexpected error: $error');
    return const DataFailure('Something went wrong. Please try again.');
  }
}

/// Reads and writes the signed-in user's pets.
class PetRepository {
  const PetRepository(this.uid);

  final String uid;

  /// Live list of pets, newest first.
  ///
  /// A snapshot listener rather than a one-shot read: adding a pet on the Pets
  /// tab updates the dashboard's pet switcher with no manual refresh, which is
  /// the real-time synchronisation the brief asks to see demonstrated.
  Stream<List<Pet>> watchPets() {
    return Refs.pets(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Pet.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Stream<Pet?> watchPet(String petId) {
    return Refs.pet(uid, petId).snapshots().map((snap) {
      final Map<String, dynamic>? data = snap.data();
      return data == null ? null : Pet.fromMap(snap.id, data);
    }).handleError((Object e) => throw DataFailure.from(e));
  }

  Future<List<Pet>> fetchPets() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap =
          await Refs.pets(uid).orderBy('createdAt', descending: true).get();
      return snap.docs
          .map((d) => Pet.fromMap(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<String> addPet(Pet pet) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.pets(uid).add(pet.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Writes the whole document instead of merging fields into it.
  ///
  /// `toMap` prunes nulls, so a partial `update` silently kept the old value of
  /// anything the owner had cleared — removing a pet's photo, a medicine's end
  /// date or a vet's phone number appeared to work and then came back. A full
  /// `set` makes the stored document match the form exactly.
  Future<void> updatePet(Pet pet) async {
    try {
      await Refs.pet(uid, pet.id).set(pet.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Deletes a pet and every care record beneath it.
  ///
  /// Firestore does not cascade deletes, so leaving the subcollections behind
  /// would orphan the data — still billable, still readable by the owner, and
  /// invisible in the UI. Each subcollection is cleared in chunked batches
  /// (Firestore caps a batch at 500 writes) before the parent is removed.
  Future<void> deletePet(String petId) async {
    const List<String> subcollections = <String>[
      'feedingSchedules',
      'feedingRecords',
      'exerciseRecords',
      'medicines',
      'medicineDoses',
      'vaccinations',
      'groomingRecords',
      'appointments',
      'medicalHistory',
      'aiInsights',
    ];

    try {
      for (final String name in subcollections) {
        await _deleteCollection(Refs.pet(uid, petId).collection(name));
      }
      await Refs.pet(uid, petId).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> ref, {
    int chunkSize = 200,
  }) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> snap =
          await ref.limit(chunkSize).get();
      if (snap.docs.isEmpty) return;

      final WriteBatch batch = Refs.db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snap.docs.length < chunkSize) return;
    }
  }
}
