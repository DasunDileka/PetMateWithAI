import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firestore_refs.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/exercise.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/vaccination.dart';
import '../pets/pet_repository.dart' show DataFailure;

/// All day-to-day care data for one pet: feeding, exercise, medication,
/// vaccination and grooming.
///
/// Query design notes (performance rubric):
///  * Every query is scoped to one pet and bounded by either a date range or an
///    explicit `limit` — nothing here can fan out across a whole account.
///  * Range filters and `orderBy` always use the *same* field, which Firestore
///    serves from the automatic single-field index. No composite indexes are
///    required for the app to run.
///  * Same-day lookups use the denormalised `dayKey` equality filter instead of
///    a timestamp range, so they stay a single index seek.
class CareRepository {
  const CareRepository({required this.uid, required this.petId});

  final String uid;
  final String petId;

  /// How much history the analysis window needs. Queries are capped to this so
  /// a pet with years of records still loads a bounded amount.
  static const int analysisWindowDays = 14;

  DateTime get _windowStart {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: analysisWindowDays - 1));
  }

  // ==================================================== feeding schedules

  Stream<List<FeedingSchedule>> watchFeedingSchedules() {
    return Refs.feedingSchedules(uid, petId)
        .snapshots()
        .map((snap) {
          final List<FeedingSchedule> list = snap.docs
              .map((d) => FeedingSchedule.fromMap(d.id, d.data()))
              .toList();
          // Sorted client-side: the list is small (a handful of slots) and this
          // avoids needing an index on two fields.
          list.sort((a, b) =>
              (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
          return list;
        })
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addFeedingSchedule(FeedingSchedule schedule) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.feedingSchedules(uid, petId).add(schedule.toMap());
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
  Future<void> updateFeedingSchedule(FeedingSchedule schedule) async {
    try {
      await Refs.feedingSchedules(uid, petId)
          .doc(schedule.id)
          .set(schedule.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteFeedingSchedule(String id) async {
    try {
      await Refs.feedingSchedules(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // ====================================================== feeding records

  /// Feeding records for a single day, via the denormalised day key.
  Stream<List<FeedingRecord>> watchFeedingRecordsForDay(DateTime day) {
    return Refs.feedingRecords(uid, petId)
        .where('dayKey', isEqualTo: dayKeyOf(day))
        .snapshots()
        .map((snap) {
          final List<FeedingRecord> list = snap.docs
              .map((d) => FeedingRecord.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
          return list;
        })
        .handleError((Object e) => throw DataFailure.from(e));
  }

  /// Feeding records across the analysis window, used by the statistics layer.
  Stream<List<FeedingRecord>> watchRecentFeedingRecords() {
    return Refs.feedingRecords(uid, petId)
        .where('scheduledAt', isGreaterThanOrEqualTo: _windowStart)
        .orderBy('scheduledAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => FeedingRecord.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  /// Marks a scheduled slot as completed for [day], creating the record if the
  /// owner has not interacted with that slot yet.
  ///
  /// A deterministic document id (`scheduleId_dayKey`) makes this idempotent:
  /// double-tapping "mark done" updates one document instead of creating two,
  /// which would otherwise corrupt the completion statistics.
  Future<void> markFeedingCompleted({
    required FeedingSchedule schedule,
    required DateTime day,
    String? notes,
  }) async {
    final String docId = '${schedule.id}_${dayKeyOf(day)}';
    final DateTime due = schedule.dueOn(day);

    final FeedingRecord record = FeedingRecord(
      id: docId,
      scheduledAt: due,
      status: CareStatus.completed,
      scheduleId: schedule.id,
      label: schedule.label,
      completedAt: DateTime.now(),
      foodType: schedule.foodType,
      quantity: schedule.quantity,
      unit: schedule.unit,
      notes: notes,
    );

    try {
      await Refs.feedingRecords(uid, petId)
          .doc(docId)
          .set(record.toMap(), SetOptions(merge: true));
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> setFeedingStatus({
    required FeedingSchedule schedule,
    required DateTime day,
    required CareStatus status,
  }) async {
    final String docId = '${schedule.id}_${dayKeyOf(day)}';
    final FeedingRecord record = FeedingRecord(
      id: docId,
      scheduledAt: schedule.dueOn(day),
      status: status,
      scheduleId: schedule.id,
      label: schedule.label,
      completedAt: status == CareStatus.completed ? DateTime.now() : null,
      foodType: schedule.foodType,
      quantity: schedule.quantity,
      unit: schedule.unit,
    );

    try {
      await Refs.feedingRecords(uid, petId)
          .doc(docId)
          .set(record.toMap(), SetOptions(merge: true));
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// An unscheduled feeding the owner logs directly.
  Future<void> addAdHocFeeding(FeedingRecord record) async {
    try {
      await Refs.feedingRecords(uid, petId).add(record.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // ============================================================== exercise

  Stream<List<ExerciseRecord>> watchRecentExercise() {
    return Refs.exercise(uid, petId)
        .where('occurredAt', isGreaterThanOrEqualTo: _windowStart)
        .orderBy('occurredAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ExerciseRecord.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  /// Paged history for the full exercise log.
  Future<List<ExerciseRecord>> fetchExercisePage({
    DateTime? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = Refs.exercise(uid, petId)
          .orderBy('occurredAt', descending: true)
          .limit(limit);
      if (startAfter != null) q = q.startAfter(<Object>[startAfter]);

      final QuerySnapshot<Map<String, dynamic>> snap = await q.get();
      return snap.docs
          .map((d) => ExerciseRecord.fromMap(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<String> addExercise(ExerciseRecord record) async {
    try {
      // A tracked walk can produce thousands of GPS samples. Downsampling
      // before the write keeps the document well inside Firestore's 1 MiB
      // limit while preserving the shape of the route.
      final ExerciseRecord toSave = record.route.length > 200
          ? ExerciseRecord(
              id: record.id,
              type: record.type,
              durationMinutes: record.durationMinutes,
              occurredAt: record.occurredAt,
              distanceKm: record.distanceKm,
              notes: record.notes,
              route: _downsample(record.route, 200),
            )
          : record;

      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.exercise(uid, petId).add(toSave.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> updateExercise(ExerciseRecord record) async {
    try {
      await Refs.exercise(uid, petId).doc(record.id).set(record.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteExercise(String id) async {
    try {
      await Refs.exercise(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  static List<TrackPoint> _downsample(List<TrackPoint> points, int target) {
    if (points.length <= target) return points;
    final double step = points.length / target;
    final List<TrackPoint> out = <TrackPoint>[];
    for (int i = 0; i < target; i++) {
      out.add(points[(i * step).floor()]);
    }
    // Always keep the final fix so the route ends where the walk did.
    if (out.last != points.last) out.add(points.last);
    return out;
  }

  // ============================================================== medicine

  Stream<List<Medicine>> watchMedicines() {
    return Refs.medicines(uid, petId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Medicine.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Stream<List<MedicineDose>> watchRecentDoses() {
    return Refs.medicineDoses(uid, petId)
        .where('dueAt', isGreaterThanOrEqualTo: _windowStart)
        .orderBy('dueAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MedicineDose.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addMedicine(Medicine medicine) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.medicines(uid, petId).add(medicine.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> updateMedicine(Medicine medicine) async {
    try {
      await Refs.medicines(uid, petId).doc(medicine.id).set(medicine.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteMedicine(String id) async {
    try {
      await Refs.medicines(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Records the outcome of one dose. The id is derived from the medicine and
  /// the exact due time, so the same dose can never be logged twice.
  Future<void> setDoseStatus({
    required Medicine medicine,
    required DateTime dueAt,
    required CareStatus status,
    String? notes,
  }) async {
    final String docId =
        '${medicine.id}_${dueAt.millisecondsSinceEpoch ~/ 60000}';

    final MedicineDose dose = MedicineDose(
      id: docId,
      medicineId: medicine.id,
      medicineName: medicine.name,
      dueAt: dueAt,
      status: status,
      recordedAt: DateTime.now(),
      notes: notes,
    );

    try {
      await Refs.medicineDoses(uid, petId)
          .doc(docId)
          .set(dose.toMap(), SetOptions(merge: true));
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // =========================================================== vaccination

  Stream<List<Vaccination>> watchVaccinations() {
    return Refs.vaccinations(uid, petId)
        .orderBy('administeredAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Vaccination.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addVaccination(Vaccination vaccination) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.vaccinations(uid, petId).add(vaccination.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> updateVaccination(Vaccination vaccination) async {
    try {
      await Refs.vaccinations(uid, petId)
          .doc(vaccination.id)
          .set(vaccination.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteVaccination(String id) async {
    try {
      await Refs.vaccinations(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  // ============================================================== grooming

  Stream<List<GroomingRecord>> watchGrooming() {
    return Refs.grooming(uid, petId)
        .snapshots()
        .map((snap) {
          final List<GroomingRecord> list = snap.docs
              .map((d) => GroomingRecord.fromMap(d.id, d.data()))
              .toList();
          // Soonest-due first, with unscheduled tasks last.
          list.sort((a, b) {
            final DateTime? ad = a.nextDueAt;
            final DateTime? bd = b.nextDueAt;
            if (ad == null && bd == null) return a.type.index.compareTo(b.type.index);
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });
          return list;
        })
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<String> addGrooming(GroomingRecord record) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.grooming(uid, petId).add(record.toMap());
      return ref.id;
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> updateGrooming(GroomingRecord record) async {
    try {
      await Refs.grooming(uid, petId).doc(record.id).set(record.toMap());
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  Future<void> deleteGrooming(String id) async {
    try {
      await Refs.grooming(uid, petId).doc(id).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }
}
