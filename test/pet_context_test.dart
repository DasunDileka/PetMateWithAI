import 'package:flutter_test/flutter_test.dart';
import 'package:petmate/features/ai/pet_context_builder.dart';
import 'package:petmate/shared/models/appointment.dart';
import 'package:petmate/shared/models/care_enums.dart';
import 'package:petmate/shared/models/exercise.dart';
import 'package:petmate/shared/models/feeding.dart';
import 'package:petmate/shared/models/grooming.dart';
import 'package:petmate/shared/models/medicine.dart';
import 'package:petmate/shared/models/pet.dart';
import 'package:petmate/shared/models/vaccination.dart';

/// Tests for the AI context block and, in particular, its fingerprint.
///
/// The fingerprint is the whole basis of the insight cache: a cached insight is
/// reused only while the fingerprint is unchanged. If it moves for reasons that
/// have nothing to do with the pet's data, the cache silently stops working and
/// every visit to the dashboard spends a model call.
void main() {
  Pet buildPet() => Pet(
        id: 'p1',
        name: 'Bruno',
        species: PetSpecies.dog,
        breed: 'Labrador',
        dateOfBirth: DateTime(2023, 4, 12),
        weightKg: 18,
        createdAt: DateTime(2026, 7, 1),
      );

  PetContext buildAt(DateTime now, {List<ExerciseRecord> exercise = const <ExerciseRecord>[]}) =>
      PetContextBuilder.build(
        pet: buildPet(),
        feedingSchedules: const <FeedingSchedule>[],
        feedingRecords: const <FeedingRecord>[],
        exercise: exercise,
        medicines: const <Medicine>[],
        doses: const <MedicineDose>[],
        vaccinations: const <Vaccination>[],
        grooming: const <GroomingRecord>[],
        appointments: const <Appointment>[],
        now: now,
      );

  group('fingerprint', () {
    test('does not change as the clock advances within a day', () {
      // Regression: the context text carries the time of day so the model can
      // say "this evening", and the fingerprint was taken over that same text.
      // Every minute therefore produced a new key, no cached insight ever
      // matched, and the six-hour cache was dead on arrival.
      final PetContext morning = buildAt(DateTime(2026, 8, 20, 9, 5));
      final PetContext evening = buildAt(DateTime(2026, 8, 20, 19, 47));

      expect(evening.fingerprint, morning.fingerprint);
    });

    test('still carries the time of day to the model', () {
      final PetContext ctx = buildAt(DateTime(2026, 8, 20, 19, 47));
      expect(ctx.text, contains('7:47 pm'));
    });

    test('changes when the day rolls over', () {
      final PetContext today = buildAt(DateTime(2026, 8, 20, 19, 0));
      final PetContext tomorrow = buildAt(DateTime(2026, 8, 21, 19, 0));

      expect(tomorrow.fingerprint, isNot(today.fingerprint));
    });

    test('changes when the pet\'s recorded data changes', () {
      final DateTime now = DateTime(2026, 8, 20, 12);
      final PetContext before = buildAt(now);
      final PetContext after = buildAt(now, exercise: <ExerciseRecord>[
        ExerciseRecord(
          id: 'e1',
          type: ExerciseType.walk,
          durationMinutes: 30,
          occurredAt: now.subtract(const Duration(hours: 2)),
        ),
      ]);

      expect(after.fingerprint, isNot(before.fingerprint));
    });
  });

  test('context never contains owner identity', () {
    // The privacy rule the builder documents: only pet-care facts leave the
    // device.
    final String text = buildAt(DateTime(2026, 8, 20, 12)).text;
    expect(text, isNot(contains('@')));
    expect(text, isNot(contains('p1')));
  });
}
