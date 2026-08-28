import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firestore_refs.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/veterinarian.dart';
import '../pets/pet_repository.dart' show DataFailure;

/// Veterinarian contacts, appointments and the unified medical history.
///
/// Vets are stored per *user*; appointments and medical history per *pet*.
/// That split reflects how the data is actually used: one clinic serves the
/// whole household, but a clinical record belongs to one animal.
class VetRepository {
  const VetRepository({required this.uid});

  final String uid;

  // ======================================================== veterinarians

  Stream<List<Veterinarian>> watchVeterinarians() {
    return Refs.veterinarians(uid)
        .orderBy('doctorName')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Veterinarian.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addVeterinarian(Veterinarian vet) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.veterinarians(uid).add(vet.toMap());
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
  Future<void> updateVeterinarian(Veterinarian vet) async {
    try {
      await Refs.veterinarians(uid).doc(vet.id).set(vet.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteVeterinarian(String id) async {
    try {
      await Refs.veterinarians(uid).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // ========================================================= appointments

  Stream<List<Appointment>> watchAppointments(String petId) {
    return Refs.appointments(uid, petId)
        .orderBy('scheduledAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Appointment.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  /// Only future appointments — used by the dashboard and the reminder
  /// scheduler, where loading the full history would be wasteful.
  Stream<List<Appointment>> watchUpcomingAppointments(String petId) {
    return Refs.appointments(uid, petId)
        .where('scheduledAt', isGreaterThanOrEqualTo: DateTime.now())
        .orderBy('scheduledAt')
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Appointment.fromMap(d.id, d.data()))
            .where((a) => a.status == AppointmentStatus.upcoming)
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addAppointment(String petId, Appointment appointment) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.appointments(uid, petId).add(appointment.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> updateAppointment(String petId, Appointment appointment) async {
    try {
      await Refs.appointments(uid, petId)
          .doc(appointment.id)
          .set(appointment.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteAppointment(String petId, String id) async {
    try {
      await Refs.appointments(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Completes an appointment and files the outcome into the medical history
  /// in one atomic batch, so the two records can never disagree.
  Future<void> completeAppointment({
    required String petId,
    required Appointment appointment,
    required String outcome,
  }) async {
    try {
      final WriteBatch batch = Refs.db.batch();

      batch.update(
        Refs.appointments(uid, petId).doc(appointment.id),
        <String, dynamic>{
          'status': AppointmentStatus.completed.name,
          'outcome': outcome.trim(),
        },
      );

      final MedicalHistoryEntry entry = MedicalHistoryEntry(
        id: '',
        title: appointment.reason,
        occurredAt: appointment.scheduledAt,
        category: 'appointment',
        description: outcome.trim(),
        veterinarianName: appointment.veterinarianName,
        sourceCollection: 'appointments',
        sourceId: appointment.id,
        createdAt: DateTime.now(),
      );

      batch.set(Refs.medicalHistory(uid, petId).doc(), entry.toMap());

      await batch.commit();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // ===================================================== medical history

  Stream<List<MedicalHistoryEntry>> watchMedicalHistory(
    String petId, {
    int limit = 50,
  }) {
    return Refs.medicalHistory(uid, petId)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MedicalHistoryEntry.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<List<MedicalHistoryEntry>> fetchHistoryPage(
    String petId, {
    DateTime? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = Refs.medicalHistory(uid, petId)
          .orderBy('occurredAt', descending: true)
          .limit(limit);
      if (startAfter != null) q = q.startAfter(<Object>[startAfter]);

      final QuerySnapshot<Map<String, dynamic>> snap = await q.get();
      return snap.docs
          .map((d) => MedicalHistoryEntry.fromMap(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<String> addMedicalHistory(
    String petId,
    MedicalHistoryEntry entry,
  ) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.medicalHistory(uid, petId).add(entry.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteMedicalHistory(String petId, String id) async {
    try {
      await Refs.medicalHistory(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }
}
