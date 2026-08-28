import 'package:flutter_test/flutter_test.dart';
import 'package:petmate/features/analytics/care_analytics.dart';
import 'package:petmate/shared/models/care_enums.dart';
import 'package:petmate/shared/models/exercise.dart';
import 'package:petmate/shared/models/feeding.dart';
import 'package:petmate/shared/models/medicine.dart';
import 'package:petmate/shared/models/pet.dart';

/// Unit tests for the deterministic analytics engine.
///
/// These matter more than UI tests here: every figure the AI states about a pet
/// comes from this class, so a silent regression would make the assistant
/// confidently wrong. Because `CareAnalytics` is pure Dart with an injectable
/// `now`, it can be tested exhaustively without Firebase or a widget tree.
void main() {
  final DateTime now = DateTime(2026, 8, 20, 12);

  Pet buildPet() => Pet(
        id: 'p1',
        name: 'Bruno',
        species: PetSpecies.dog,
        breed: 'Labrador',
        dateOfBirth: DateTime(2023, 4, 12),
        weightKg: 18,
        createdAt: DateTime(2026, 7, 1),
      );

  ExerciseRecord exercise(int daysAgo, int minutes,
          {ExerciseType type = ExerciseType.walk}) =>
      ExerciseRecord(
        id: 'e$daysAgo-$minutes',
        type: type,
        durationMinutes: minutes,
        occurredAt: now.subtract(Duration(days: daysAgo)),
      );

  group('exerciseSeries', () {
    test('zero-fills days with no recorded exercise', () {
      final List<DailyMetric> series = CareAnalytics.exerciseSeries(
        <ExerciseRecord>[exercise(0, 30), exercise(2, 20)],
        days: 5,
        now: now,
      );

      expect(series.length, 5);
      // Oldest first: day-4, day-3, day-2, day-1, today.
      expect(series.map((DailyMetric d) => d.value).toList(),
          <double>[0, 0, 20, 0, 30]);
    });

    test('sums multiple sessions on the same day', () {
      final List<DailyMetric> series = CareAnalytics.exerciseSeries(
        <ExerciseRecord>[exercise(0, 15), exercise(0, 25)],
        days: 3,
        now: now,
      );
      expect(series.last.value, 40);
    });

    test('ignores records outside the window', () {
      final List<DailyMetric> series = CareAnalytics.exerciseSeries(
        <ExerciseRecord>[exercise(30, 60), exercise(0, 10)],
        days: 7,
        now: now,
      );
      expect(series.fold<double>(0, (a, b) => a + b.value), 10);
    });
  });

  group('trend', () {
    test('reports a decline when recent activity drops materially', () {
      // 30, 28, 25 earlier -> 18, 12 recently.
      final List<ExerciseRecord> records = <ExerciseRecord>[
        exercise(0, 12),
        exercise(1, 18),
        exercise(2, 25),
        exercise(3, 28),
        exercise(4, 30),
        exercise(5, 30),
        exercise(6, 32),
        exercise(7, 30),
      ];

      final TrendResult result = CareAnalytics.trend(
        CareAnalytics.exerciseSeries(records, days: 8, now: now),
      );

      expect(result.direction, TrendDirection.falling);
      expect(result.changePercent, lessThan(0));
      expect(result.hasData, isTrue);
    });

    test('reports stability when day-to-day variation is small', () {
      final List<ExerciseRecord> records = List<ExerciseRecord>.generate(
        10,
        (int i) => exercise(i, 20),
      );

      final TrendResult result = CareAnalytics.trend(
        CareAnalytics.exerciseSeries(records, days: 10, now: now),
      );

      expect(result.direction, TrendDirection.stable);
      expect(result.mean, 20);
    });

    test('does not claim a trend from too few data points', () {
      final TrendResult result = CareAnalytics.trend(
        CareAnalytics.exerciseSeries(
          <ExerciseRecord>[exercise(0, 20)],
          days: 3,
          now: now,
        ),
      );
      expect(result.direction, TrendDirection.insufficientData);
    });
  });

  group('feedingCompletion', () {
    test('counts only slots that were due, not future ones', () {
      final FeedingSchedule morning = FeedingSchedule(
        id: 's1',
        label: 'Morning',
        hour: 7,
        minute: 30,
        createdAt: now.subtract(const Duration(days: 30)),
      );
      // 6pm slot has not arrived yet at the 12pm 'now'.
      final FeedingSchedule evening = FeedingSchedule(
        id: 's2',
        label: 'Evening',
        hour: 18,
        minute: 0,
        createdAt: now.subtract(const Duration(days: 30)),
      );

      final CompletionStat stat = CareAnalytics.feedingCompletion(
        <FeedingSchedule>[morning, evening],
        <FeedingRecord>[],
        days: 1,
        now: now,
      );

      // Only the morning slot was due today.
      expect(stat.expected, 1);
      expect(stat.completed, 0);
    });

    test('ignores schedules created after the day in question', () {
      final FeedingSchedule createdToday = FeedingSchedule(
        id: 's3',
        label: 'Morning',
        hour: 7,
        minute: 0,
        createdAt: now,
      );

      final CompletionStat stat = CareAnalytics.feedingCompletion(
        <FeedingSchedule>[createdToday],
        <FeedingRecord>[],
        days: 7,
        now: now,
      );

      // Only today counts, and only because the slot time has passed.
      expect(stat.expected, 1);
    });

    test('measures completion against the plan', () {
      final FeedingSchedule morning = FeedingSchedule(
        id: 's1',
        label: 'Morning',
        hour: 7,
        minute: 0,
        createdAt: now.subtract(const Duration(days: 30)),
      );

      final List<FeedingRecord> records = <FeedingRecord>[
        FeedingRecord(
          id: 'r1',
          scheduledAt: DateTime(now.year, now.month, now.day, 7),
          status: CareStatus.completed,
          scheduleId: 's1',
        ),
      ];

      final CompletionStat stat = CareAnalytics.feedingCompletion(
        <FeedingSchedule>[morning],
        records,
        days: 1,
        now: now,
      );

      expect(stat.expected, 1);
      expect(stat.completed, 1);
      expect(stat.percent, 100);
    });
  });

  group('medicationAdherence', () {
    test('counts doses due up to now and those recorded as taken', () {
      final Medicine medicine = Medicine(
        id: 'm1',
        name: 'Joint supplement',
        dosage: '1 tablet',
        frequency: MedicineFrequency.onceDaily, // default hour 08:00
        startDate: now.subtract(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 2)),
      );

      final List<MedicineDose> doses = <MedicineDose>[
        MedicineDose(
          id: 'd1',
          medicineId: 'm1',
          medicineName: 'Joint supplement',
          dueAt: DateTime(now.year, now.month, now.day, 8),
          status: CareStatus.completed,
        ),
      ];

      final CompletionStat stat = CareAnalytics.medicationAdherence(
        <Medicine>[medicine],
        doses,
        days: 3,
        now: now,
      );

      // Three days in the window, each with an 08:00 dose already due.
      expect(stat.expected, 3);
      expect(stat.completed, 1);
    });

    test('as-needed medication never counts against adherence', () {
      final Medicine asNeeded = Medicine(
        id: 'm2',
        name: 'Pain relief',
        dosage: 'as directed',
        frequency: MedicineFrequency.asNeeded,
        startDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 5)),
      );

      final CompletionStat stat = CareAnalytics.medicationAdherence(
        <Medicine>[asNeeded],
        <MedicineDose>[],
        days: 7,
        now: now,
      );

      expect(stat.expected, 0);
      expect(stat.hasData, isFalse);
    });
  });

  group('detectAnomalies', () {
    test('flags a sustained drop against the pet\'s own baseline', () {
      final List<ExerciseRecord> records = <ExerciseRecord>[
        // Recent three days: very low.
        exercise(0, 5), exercise(1, 6), exercise(2, 7),
        // Baseline: consistently high.
        exercise(3, 35), exercise(4, 34), exercise(5, 36),
        exercise(6, 33), exercise(7, 35), exercise(8, 34),
        exercise(9, 36), exercise(10, 35),
      ];

      final List<CareAnomaly> found = CareAnalytics.detectAnomalies(
        pet: buildPet(),
        exercise: records,
        feedingSchedules: const <FeedingSchedule>[],
        feedingRecords: const <FeedingRecord>[],
        medicines: const <Medicine>[],
        doses: const <MedicineDose>[],
        now: now,
      );

      expect(found.any((CareAnomaly a) => a.type == CareType.exercise), isTrue);
    });

    test('does not flag a pet with no established baseline', () {
      final List<CareAnomaly> found = CareAnalytics.detectAnomalies(
        pet: buildPet(),
        exercise: <ExerciseRecord>[exercise(9, 5)],
        feedingSchedules: const <FeedingSchedule>[],
        feedingRecords: const <FeedingRecord>[],
        medicines: const <Medicine>[],
        doses: const <MedicineDose>[],
        now: now,
      );

      expect(
        found.any((CareAnomaly a) => a.title == 'Activity lower than usual'),
        isFalse,
      );
    });

    test('flags repeated missed feedings', () {
      final List<FeedingRecord> records = <FeedingRecord>[
        FeedingRecord(
          id: 'f1',
          scheduledAt: now.subtract(const Duration(days: 1)),
          status: CareStatus.missed,
        ),
        FeedingRecord(
          id: 'f2',
          scheduledAt: now,
          status: CareStatus.missed,
        ),
      ];

      final List<CareAnomaly> found = CareAnalytics.detectAnomalies(
        pet: buildPet(),
        exercise: const <ExerciseRecord>[],
        feedingSchedules: const <FeedingSchedule>[],
        feedingRecords: records,
        medicines: const <Medicine>[],
        doses: const <MedicineDose>[],
        now: now,
      );

      expect(found.any((CareAnomaly a) => a.type == CareType.feeding), isTrue);
    });

    test('anomaly wording never asserts a diagnosis', () {
      final List<ExerciseRecord> records = <ExerciseRecord>[
        exercise(0, 4), exercise(1, 5), exercise(2, 6),
        exercise(3, 35), exercise(4, 34), exercise(5, 36),
        exercise(6, 33), exercise(7, 35),
      ];

      final List<CareAnomaly> found = CareAnalytics.detectAnomalies(
        pet: buildPet(),
        exercise: records,
        feedingSchedules: const <FeedingSchedule>[],
        feedingRecords: const <FeedingRecord>[],
        medicines: const <Medicine>[],
        doses: const <MedicineDose>[],
        now: now,
      );

      for (final CareAnomaly a in found) {
        final String text = '${a.title} ${a.description}'.toLowerCase();
        for (final String banned in <String>[
          'diagnos',
          'disease',
          'illness',
          'suffering from',
          'you should give',
        ]) {
          expect(text.contains(banned), isFalse,
              reason: 'Anomaly text must not contain "$banned": $text');
        }
      }
    });
  });

  group('Pet derived fields', () {
    test('calculates age in whole years', () {
      final Pet pet = buildPet();
      expect(pet.ageInYears, isNotNull);
      expect(pet.ageLabel, contains('year'));
    });

    test('handles a missing date of birth without throwing', () {
      final Pet pet = Pet(
        id: 'x',
        name: 'Unknown',
        species: PetSpecies.other,
        createdAt: now,
      );
      expect(pet.ageInMonths, isNull);
      expect(pet.ageLabel, 'Age unknown');
    });
  });
}
