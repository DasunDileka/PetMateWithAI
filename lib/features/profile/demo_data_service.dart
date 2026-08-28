import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firestore_refs.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/exercise.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';
import '../../shared/models/veterinarian.dart';

/// Seeds two contrasting demonstration pets with realistic care history.
///
/// The two profiles are deliberately different — an active young Labrador with
/// a declining activity trend and two missed feedings, versus a settled senior
/// cat on daily medication — so that the AI's personalisation is *observable*:
/// the same question asked about each pet must produce visibly different
/// answers grounded in different numbers.
///
/// Everything is written through the same repositories and security rules the
/// app uses normally; nothing here bypasses validation.
class DemoDataService {
  const DemoDataService(this.uid);

  final String uid;

  /// Deterministic generator so a re-seed produces the same demonstration and
  /// the viva is reproducible.
  static final math.Random _rng = math.Random(20260820);

  Future<DemoSeedResult> seed() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final String vetId = await _seedVeterinarian();

    final String brunoId = await _seedBruno(today, vetId);
    final String lunaId = await _seedLuna(today, vetId);

    return DemoSeedResult(
      petIds: <String>[brunoId, lunaId],
      activePetId: brunoId,
    );
  }

  // ------------------------------------------------------------------ vet

  Future<String> _seedVeterinarian() async {
    final DocumentReference<Map<String, dynamic>> ref =
        await Refs.veterinarians(uid).add(
      Veterinarian(
        id: '',
        doctorName: 'Dr Anita Perera',
        clinicName: 'Colombo Animal Clinic',
        specialisation: 'Small animal medicine',
        phone: '+94 11 234 5678',
        email: 'reception@colomboanimalclinic.lk',
        address: '42 Galle Road, Colombo 03',
        latitude: 6.9014,
        longitude: 79.8560,
        notes: 'Open Mon–Sat. Emergency line after 8pm.',
        createdAt: DateTime.now(),
      ).toMap(),
    );
    return ref.id;
  }

  // ---------------------------------------------------------------- Bruno

  /// Bruno: 3-year-old Labrador. Active, but with a *deliberately declining*
  /// exercise trend over the last five days and two missed feedings, so the
  /// anomaly detector and the AI have something real to report.
  Future<String> _seedBruno(DateTime today, String vetId) async {
    final DocumentReference<Map<String, dynamic>> petRef =
        await Refs.pets(uid).add(
      Pet(
        id: '',
        name: 'Bruno',
        species: PetSpecies.dog,
        breed: 'Labrador Retriever',
        gender: PetGender.male,
        dateOfBirth: DateTime(today.year - 3, 4, 12),
        weightKg: 18.0,
        notes: 'Loves the park. Slightly sensitive to chicken.',
        primaryVetId: vetId,
        createdAt: today.subtract(const Duration(days: 30)),
      ).toMap(),
    );
    final String petId = petRef.id;

    // -- feeding schedules --------------------------------------------------
    final WriteBatch batch = Refs.db.batch();

    final DocumentReference<Map<String, dynamic>> morningRef =
        Refs.feedingSchedules(uid, petId).doc();
    batch.set(
      morningRef,
      FeedingSchedule(
        id: '',
        label: 'Morning',
        hour: 7,
        minute: 30,
        foodType: 'Dry kibble',
        quantity: 200,
        createdAt: today.subtract(const Duration(days: 30)),
      ).toMap(),
    );

    final DocumentReference<Map<String, dynamic>> eveningRef =
        Refs.feedingSchedules(uid, petId).doc();
    batch.set(
      eveningRef,
      FeedingSchedule(
        id: '',
        label: 'Evening',
        hour: 18,
        minute: 30,
        foodType: 'Dry kibble',
        quantity: 200,
        createdAt: today.subtract(const Duration(days: 30)),
      ).toMap(),
    );

    await batch.commit();

    // -- feeding records: 12 of 14 completed over the last 7 days ----------
    // Two evening feedings (3 and 5 days ago) are recorded as missed, which is
    // what makes "12 of 14" a measured figure rather than a claim.
    const Set<int> missedEvenings = <int>{3, 5};

    final WriteBatch feedBatch = Refs.db.batch();
    for (int daysAgo = 6; daysAgo >= 0; daysAgo--) {
      final DateTime day = today.subtract(Duration(days: daysAgo));

      for (final ({DocumentReference<Map<String, dynamic>> ref, String label, int hour, int minute}) slot
          in <({DocumentReference<Map<String, dynamic>> ref, String label, int hour, int minute})>[
        (ref: morningRef, label: 'Morning', hour: 7, minute: 30),
        (ref: eveningRef, label: 'Evening', hour: 18, minute: 30),
      ]) {
        final DateTime due =
            DateTime(day.year, day.month, day.day, slot.hour, slot.minute);

        // Today's evening meal is left pending so the dashboard has a live
        // outstanding task to demonstrate.
        if (daysAgo == 0 && slot.label == 'Evening') continue;

        final bool missed =
            slot.label == 'Evening' && missedEvenings.contains(daysAgo);

        feedBatch.set(
          Refs.feedingRecords(uid, petId).doc('${slot.ref.id}_${dayKeyOf(day)}'),
          FeedingRecord(
            id: '',
            scheduledAt: due,
            status: missed ? CareStatus.missed : CareStatus.completed,
            scheduleId: slot.ref.id,
            label: slot.label,
            completedAt: missed ? null : due.add(const Duration(minutes: 6)),
            foodType: 'Dry kibble',
            quantity: 200,
            notes: missed ? 'Not eaten' : null,
          ).toMap(),
        );
      }
    }
    await feedBatch.commit();

    // -- exercise: a clear downward trend over the last five days ----------
    // Mon 30, Tue 28, Wed 25, Thu 18, Fri 12 — the pattern the brief uses as
    // its worked example of trend analysis.
    const List<int> recentMinutes = <int>[12, 18, 25, 28, 30];

    final WriteBatch exBatch = Refs.db.batch();
    for (int daysAgo = 0; daysAgo < 14; daysAgo++) {
      final DateTime day = today.subtract(Duration(days: daysAgo));

      final int minutes = daysAgo < recentMinutes.length
          ? recentMinutes[daysAgo]
          // Earlier baseline sits comfortably higher, so the recent decline is
          // statistically detectable rather than noise.
          : 28 + _rng.nextInt(10);

      if (minutes <= 0) continue;

      final DateTime when = DateTime(day.year, day.month, day.day, 17, 30);

      exBatch.set(
        Refs.exercise(uid, petId).doc(),
        ExerciseRecord(
          id: '',
          type: daysAgo % 4 == 0 ? ExerciseType.play : ExerciseType.walk,
          durationMinutes: minutes,
          occurredAt: when,
          distanceKm: daysAgo % 4 == 0 ? null : minutes * 0.075,
          notes: daysAgo == 0 ? 'Seemed less interested than usual' : null,
        ).toMap(),
      );
    }
    await exBatch.commit();

    // -- vaccination: next dose due in 5 days ------------------------------
    await Refs.vaccinations(uid, petId).add(
      Vaccination(
        id: '',
        vaccineName: 'Rabies',
        administeredAt: today.subtract(const Duration(days: 360)),
        nextDueAt: today.add(const Duration(days: 5)),
        veterinarianId: vetId,
        veterinarianName: 'Dr Anita Perera',
        batchNumber: 'RB-2291',
        createdAt: today.subtract(const Duration(days: 360)),
      ).toMap(),
    );

    await Refs.vaccinations(uid, petId).add(
      Vaccination(
        id: '',
        vaccineName: 'DHPP booster',
        administeredAt: today.subtract(const Duration(days: 200)),
        nextDueAt: today.add(const Duration(days: 165)),
        veterinarianId: vetId,
        veterinarianName: 'Dr Anita Perera',
        createdAt: today.subtract(const Duration(days: 200)),
      ).toMap(),
    );

    // -- grooming: bath due in 2 days --------------------------------------
    await Refs.grooming(uid, petId).add(
      GroomingRecord(
        id: '',
        type: GroomingType.bath,
        lastCompletedAt: today.subtract(const Duration(days: 28)),
        nextDueAt: today.add(const Duration(days: 2)),
        intervalDays: 30,
        createdAt: today.subtract(const Duration(days: 28)),
      ).toMap(),
    );

    await Refs.grooming(uid, petId).add(
      GroomingRecord(
        id: '',
        type: GroomingType.nailTrim,
        lastCompletedAt: today.subtract(const Duration(days: 14)),
        nextDueAt: today.add(const Duration(days: 7)),
        intervalDays: 21,
        createdAt: today.subtract(const Duration(days: 14)),
      ).toMap(),
    );

    // -- appointment: tomorrow at 10:30 ------------------------------------
    await Refs.appointments(uid, petId).add(
      Appointment(
        id: '',
        scheduledAt: DateTime(today.year, today.month, today.day, 10, 30)
            .add(const Duration(days: 1)),
        reason: 'Routine check-up',
        veterinarianId: vetId,
        veterinarianName: 'Dr Anita Perera',
        clinicName: 'Colombo Animal Clinic',
        notes: 'Mention the drop in activity this week.',
        createdAt: today.subtract(const Duration(days: 3)),
      ).toMap(),
    );

    // -- medical history ---------------------------------------------------
    await Refs.medicalHistory(uid, petId).add(
      MedicalHistoryEntry(
        id: '',
        title: 'Annual health check',
        occurredAt: today.subtract(const Duration(days: 200)),
        category: 'appointment',
        description:
            'Healthy. Weight 17.6 kg. Teeth in good condition. DHPP booster '
            'given.',
        veterinarianName: 'Dr Anita Perera',
        createdAt: today.subtract(const Duration(days: 200)),
      ).toMap(),
    );

    return petId;
  }

  // ----------------------------------------------------------------- Luna

  /// Luna: 9-year-old senior cat on a daily joint supplement. Consistent
  /// routine, good adherence — the deliberate contrast to Bruno.
  Future<String> _seedLuna(DateTime today, String vetId) async {
    final DocumentReference<Map<String, dynamic>> petRef =
        await Refs.pets(uid).add(
      Pet(
        id: '',
        name: 'Luna',
        species: PetSpecies.cat,
        breed: 'British Shorthair',
        gender: PetGender.female,
        // Anchored to the current month so the derived age is exactly 9 years
        // whenever the dataset is seeded, matching the preview copy.
        dateOfBirth: DateTime(today.year - 9, today.month, 3),
        weightKg: 4.6,
        notes: 'Indoor cat. Prefers quiet. Stiff after long naps.',
        primaryVetId: vetId,
        createdAt: today.subtract(const Duration(days: 30)),
      ).toMap(),
    );
    final String petId = petRef.id;

    // -- feeding: three small meals, fully completed -----------------------
    final WriteBatch batch = Refs.db.batch();
    final List<({String label, int hour, int minute, DocumentReference<Map<String, dynamic>> ref})>
        slots = <({String label, int hour, int minute, DocumentReference<Map<String, dynamic>> ref})>[
      (label: 'Morning', hour: 7, minute: 0, ref: Refs.feedingSchedules(uid, petId).doc()),
      (label: 'Midday', hour: 13, minute: 0, ref: Refs.feedingSchedules(uid, petId).doc()),
      (label: 'Evening', hour: 19, minute: 0, ref: Refs.feedingSchedules(uid, petId).doc()),
    ];

    for (final slot in slots) {
      batch.set(
        slot.ref,
        FeedingSchedule(
          id: '',
          label: slot.label,
          hour: slot.hour,
          minute: slot.minute,
          foodType: 'Wet food',
          quantity: 70,
          createdAt: today.subtract(const Duration(days: 30)),
        ).toMap(),
      );
    }
    await batch.commit();

    final WriteBatch feedBatch = Refs.db.batch();
    for (int daysAgo = 6; daysAgo >= 0; daysAgo--) {
      final DateTime day = today.subtract(Duration(days: daysAgo));
      for (final slot in slots) {
        final DateTime due =
            DateTime(day.year, day.month, day.day, slot.hour, slot.minute);
        if (due.isAfter(DateTime.now())) continue;

        feedBatch.set(
          Refs.feedingRecords(uid, petId).doc('${slot.ref.id}_${dayKeyOf(day)}'),
          FeedingRecord(
            id: '',
            scheduledAt: due,
            status: CareStatus.completed,
            scheduleId: slot.ref.id,
            label: slot.label,
            completedAt: due.add(const Duration(minutes: 4)),
            foodType: 'Wet food',
            quantity: 70,
          ).toMap(),
        );
      }
    }
    await feedBatch.commit();

    // -- exercise: short, steady indoor play -------------------------------
    final WriteBatch exBatch = Refs.db.batch();
    for (int daysAgo = 0; daysAgo < 14; daysAgo++) {
      if (daysAgo % 3 == 2) continue; // rest days
      final DateTime day = today.subtract(Duration(days: daysAgo));
      exBatch.set(
        Refs.exercise(uid, petId).doc(),
        ExerciseRecord(
          id: '',
          type: ExerciseType.play,
          durationMinutes: 10 + _rng.nextInt(6),
          occurredAt: DateTime(day.year, day.month, day.day, 20, 0),
          notes: null,
        ).toMap(),
      );
    }
    await exBatch.commit();

    // -- medicine: daily joint supplement, good adherence ------------------
    final DocumentReference<Map<String, dynamic>> medRef =
        await Refs.medicines(uid, petId).add(
      Medicine(
        id: '',
        name: 'Joint supplement',
        dosage: '1 tablet',
        frequency: MedicineFrequency.onceDaily,
        startDate: today.subtract(const Duration(days: 20)),
        endDate: today.add(const Duration(days: 40)),
        veterinarianId: vetId,
        veterinarianName: 'Dr Anita Perera',
        notes: 'Give with the morning meal.',
        createdAt: today.subtract(const Duration(days: 20)),
      ).toMap(),
    );

    final WriteBatch doseBatch = Refs.db.batch();
    for (int daysAgo = 6; daysAgo >= 0; daysAgo--) {
      final DateTime day = today.subtract(Duration(days: daysAgo));
      final DateTime due = DateTime(day.year, day.month, day.day, 8);
      if (due.isAfter(DateTime.now())) continue;

      doseBatch.set(
        Refs.medicineDoses(uid, petId)
            .doc('${medRef.id}_${due.millisecondsSinceEpoch ~/ 60000}'),
        MedicineDose(
          id: '',
          medicineId: medRef.id,
          medicineName: 'Joint supplement',
          dueAt: due,
          // One missed dose keeps the adherence figure honest rather than a
          // flat 100%.
          status: daysAgo == 4 ? CareStatus.missed : CareStatus.completed,
          recordedAt: due.add(const Duration(minutes: 10)),
        ).toMap(),
      );
    }
    await doseBatch.commit();

    // -- vaccination -------------------------------------------------------
    await Refs.vaccinations(uid, petId).add(
      Vaccination(
        id: '',
        vaccineName: 'Feline trivalent (FVRCP)',
        administeredAt: today.subtract(const Duration(days: 300)),
        nextDueAt: today.add(const Duration(days: 65)),
        veterinarianId: vetId,
        veterinarianName: 'Dr Anita Perera',
        createdAt: today.subtract(const Duration(days: 300)),
      ).toMap(),
    );

    // -- grooming ----------------------------------------------------------
    await Refs.grooming(uid, petId).add(
      GroomingRecord(
        id: '',
        type: GroomingType.nailTrim,
        lastCompletedAt: today.subtract(const Duration(days: 18)),
        nextDueAt: today.subtract(const Duration(days: 1)),
        intervalDays: 17,
        notes: 'Back claws need care.',
        createdAt: today.subtract(const Duration(days: 18)),
      ).toMap(),
    );

    // -- medical history ---------------------------------------------------
    await Refs.medicalHistory(uid, petId).add(
      MedicalHistoryEntry(
        id: '',
        title: 'Senior wellness screen',
        occurredAt: today.subtract(const Duration(days: 22)),
        category: 'appointment',
        description:
            'Mild stiffness in hind legs consistent with age. Joint supplement '
            'started. Bloods within normal range. Recheck in 8 weeks.',
        veterinarianName: 'Dr Anita Perera',
        createdAt: today.subtract(const Duration(days: 22)),
      ).toMap(),
    );

    return petId;
  }

  /// Removes every demonstration pet and the seeded vet, leaving the account
  /// otherwise intact.
  Future<int> clearAll() async {
    int removed = 0;

    final QuerySnapshot<Map<String, dynamic>> pets = await Refs.pets(uid).get();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> pet in pets.docs) {
      for (final String sub in const <String>[
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
      ]) {
        final QuerySnapshot<Map<String, dynamic>> docs =
            await pet.reference.collection(sub).get();
        final WriteBatch b = Refs.db.batch();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in docs.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }
      await pet.reference.delete();
      removed++;
    }

    final QuerySnapshot<Map<String, dynamic>> vets =
        await Refs.veterinarians(uid).get();
    final WriteBatch vetBatch = Refs.db.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> v in vets.docs) {
      vetBatch.delete(v.reference);
    }
    await vetBatch.commit();

    return removed;
  }
}

class DemoSeedResult {
  const DemoSeedResult({required this.petIds, required this.activePetId});

  final List<String> petIds;
  final String activePetId;
}
