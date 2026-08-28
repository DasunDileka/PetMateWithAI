import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/config/app_config.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/exercise.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';
import '../analytics/care_analytics.dart';

/// Everything the AI is told about a pet, plus a fingerprint of it.
class PetContext {
  const PetContext({
    required this.text,
    required this.fingerprint,
    required this.snapshot,
    required this.trend,
    required this.anomalies,
    required this.feeding,
    required this.medication,
  });

  /// The prompt-ready context block.
  final String text;

  /// Stable hash of the underlying facts. When this changes, cached AI output
  /// is stale; when it does not, the cache can be reused without a model call.
  final String fingerprint;

  final TodaySnapshot snapshot;
  final TrendResult trend;
  final List<CareAnomaly> anomalies;
  final CompletionStat feeding;
  final CompletionStat medication;
}

/// Turns a pet's Firestore records into a compact, factual context block.
///
/// Three design rules drive this class:
///
///  * **Minimise.** Only pet-care facts are included. The owner's name, email,
///    account identifiers, precise GPS coordinates and document IDs are never
///    sent to a third-party model. This is the "minimise data sent to AI
///    providers" requirement made concrete.
///  * **Aggregate, don't dump.** Statistics computed by [CareAnalytics] are
///    sent instead of raw record lists. That keeps the prompt small (cost and
///    latency) and removes any opportunity for the model to miscount.
///  * **Bound.** The result is truncated to [AppConfig.maxContextChars] so a
///    pet with years of history cannot produce an unbounded prompt.
class PetContextBuilder {
  const PetContextBuilder._();

  static PetContext build({
    required Pet pet,
    required List<FeedingSchedule> feedingSchedules,
    required List<FeedingRecord> feedingRecords,
    required List<ExerciseRecord> exercise,
    required List<Medicine> medicines,
    required List<MedicineDose> doses,
    required List<Vaccination> vaccinations,
    required List<GroomingRecord> grooming,
    required List<Appointment> appointments,
    DateTime? now,
  }) {
    final DateTime nowTs = now ?? DateTime.now();

    final TodaySnapshot snapshot = CareAnalytics.today(
      feedingSchedules: feedingSchedules,
      feedingRecords: feedingRecords,
      exercise: exercise,
      medicines: medicines,
      doses: doses,
      vaccinations: vaccinations,
      grooming: grooming,
      appointments: appointments,
      now: nowTs,
    );

    final TrendResult trend =
        CareAnalytics.trend(CareAnalytics.exerciseSeries(exercise, now: nowTs));

    final CompletionStat feedingStat = CareAnalytics.feedingCompletion(
      feedingSchedules,
      feedingRecords,
      now: nowTs,
    );

    final CompletionStat medStat = CareAnalytics.medicationAdherence(
      medicines,
      doses,
      now: nowTs,
    );

    final List<CareAnomaly> anomalies = CareAnalytics.detectAnomalies(
      pet: pet,
      exercise: exercise,
      feedingSchedules: feedingSchedules,
      feedingRecords: feedingRecords,
      medicines: medicines,
      doses: doses,
      now: nowTs,
    );

    final StringBuffer b = StringBuffer()
      ..writeln('PET CONTEXT')
      ..writeln('Today: ${_longDate(nowTs)} (${_timeOfDay(nowTs)})')
      ..writeln()
      ..writeln('PROFILE')
      ..writeln('Name: ${pet.name}')
      ..writeln('Species: ${pet.species.label}')
      ..writeln('Breed: ${pet.breed ?? 'not recorded'}')
      ..writeln('Sex: ${pet.gender.label}')
      ..writeln('Age: ${pet.ageLabel} (${pet.lifeStage})')
      ..writeln(
          'Weight: ${pet.weightKg > 0 ? '${_num(pet.weightKg)} kg' : 'not recorded'}');

    if ((pet.notes ?? '').trim().isNotEmpty) {
      b.writeln('Owner notes: ${_clip(pet.notes!.trim(), 200)}');
    }

    // ------------------------------------------------------------- today
    b
      ..writeln()
      ..writeln('TODAY SO FAR');

    if (snapshot.feedingsScheduled == 0) {
      b.writeln('Feeding: no feeding schedule has been set up.');
    } else {
      b.writeln(
          'Feeding: ${snapshot.feedingsCompleted} of ${snapshot.feedingsScheduled} '
          'scheduled feedings completed.');
      if (snapshot.pendingFeedings.isNotEmpty) {
        final String pending = snapshot.pendingFeedings
            .map((s) => '${s.label} at ${s.timeLabel}')
            .join(', ');
        b.writeln('Feeding still due: $pending.');
      }
    }

    b.writeln(snapshot.exerciseMinutes > 0
        ? 'Exercise: ${snapshot.exerciseMinutes} minutes recorded today.'
        : 'Exercise: nothing recorded today.');

    if (snapshot.dosesDue > 0) {
      b.writeln(
          'Medication: ${snapshot.dosesTaken} of ${snapshot.dosesDue} doses due today '
          'have been recorded as given.');
    } else {
      b.writeln('Medication: no doses due today.');
    }

    // ---------------------------------------------------------- upcoming
    final List<String> upcoming = <String>[];

    final Appointment? appt = snapshot.nextAppointment;
    if (appt != null) {
      upcoming.add('Vet appointment: ${appt.reason} — ${appt.whenLabel}'
          '${appt.veterinarianName == null ? '' : ' with ${appt.veterinarianName}'}.');
    }

    final Vaccination? vac = snapshot.nextVaccination;
    if (vac != null) {
      upcoming.add('Vaccination: ${vac.vaccineName} — ${vac.dueLabel.toLowerCase()}.');
    }

    final GroomingRecord? groom = snapshot.nextGrooming;
    if (groom != null) {
      upcoming.add('Grooming: ${groom.type.label} — ${groom.dueLabel.toLowerCase()}.');
    }

    b
      ..writeln()
      ..writeln('UPCOMING');
    if (upcoming.isEmpty) {
      b.writeln('Nothing scheduled.');
    } else {
      for (final String line in upcoming) {
        b.writeln(line);
      }
    }

    // ------------------------------------------------------- last 7 days
    b
      ..writeln()
      ..writeln('LAST 7 DAYS');

    b.writeln(feedingStat.hasData
        ? 'Feeding completion: ${feedingStat.completed} of ${feedingStat.expected} '
            '(${feedingStat.percent.round()}%), ${feedingStat.missed} not completed.'
        : 'Feeding completion: no scheduled feedings to measure.');

    b.writeln(medStat.hasData
        ? 'Medication adherence: ${medStat.completed} of ${medStat.expected} doses '
            '(${medStat.percent.round()}%).'
        : 'Medication adherence: no scheduled doses in this period.');

    // ------------------------------------------------- activity (14 days)
    b
      ..writeln()
      ..writeln('ACTIVITY — LAST 14 DAYS (minutes per day, oldest first)');

    if (!trend.hasData) {
      b.writeln('No exercise recorded in this period.');
    } else {
      final Iterable<DailyMetric> recent = trend.series.skip(trend.series.length - 7);
      for (final DailyMetric d in recent) {
        b.writeln('${d.weekdayLabel} ${_shortDate(d.day)}: ${d.value.round()} min');
      }
      b
        ..writeln('Average over 14 days: ${trend.mean.round()} min/day.')
        ..writeln('Trend: ${trend.direction.label.toLowerCase()} '
            '(${trend.changePercent >= 0 ? '+' : ''}${trend.changePercent.round()}% '
            'recent vs earlier).');
    }

    // ---------------------------------------------------- active medicines
    final List<Medicine> active =
        medicines.where((m) => m.isActive).toList(growable: false);
    if (active.isNotEmpty) {
      b
        ..writeln()
        ..writeln('ACTIVE MEDICATION (as recorded by the owner)');
      for (final Medicine m in active.take(5)) {
        b.writeln('${m.name} — ${m.dosage}, ${m.frequency.label.toLowerCase()}'
            '${m.endDate == null ? '' : ', until ${_shortDate(m.endDate!)}'}.');
      }
    }

    // ------------------------------------------------------- vaccinations
    if (vaccinations.isNotEmpty) {
      b
        ..writeln()
        ..writeln('VACCINATION RECORD');
      final List<Vaccination> sorted = vaccinations.toList()
        ..sort((a, c) => c.administeredAt.compareTo(a.administeredAt));
      for (final Vaccination v in sorted.take(5)) {
        b.writeln('${v.vaccineName} — given ${_shortDate(v.administeredAt)}'
            '${v.nextDueAt == null ? '' : ', next due ${_shortDate(v.nextDueAt!)}'}.');
      }
    }

    // ----------------------------------------------------------- anomalies
    if (anomalies.isNotEmpty) {
      b
        ..writeln()
        ..writeln('PATTERNS DETECTED BY THE APP (data observations, not health findings)');
      for (final CareAnomaly a in anomalies.take(3)) {
        b.writeln('- ${a.title}: ${a.description}');
      }
    }

    final String text = _clip(b.toString().trim(), AppConfig.maxContextChars);

    return PetContext(
      text: text,
      fingerprint: _fingerprint(_dateStable(text)),
      snapshot: snapshot,
      trend: trend,
      anomalies: anomalies,
      feeding: feedingStat,
      medication: medStat,
    );
  }

  // ------------------------------------------------------------- helpers

  /// SHA-256 over the context, truncated. Used purely as a cache key, so a
  /// short digest is sufficient and keeps the Firestore document small.
  static String _fingerprint(String context) {
    // The date line changes daily, which is intended: a cached insight should
    // not survive into the next day.
    return sha256.convert(utf8.encode(context)).toString().substring(0, 24);
  }

  /// The context with the clock time stripped out, used as the fingerprint
  /// source.
  ///
  /// The context text deliberately carries the time of day so the model can
  /// say "this evening" rather than "today". The *fingerprint* must not:
  /// hashing the minute meant every rebuild produced a different key, the
  /// cached insight could never match, and each visit to the dashboard spent
  /// a model call on data that had not changed. The date is kept, so a cached
  /// insight still expires when the day rolls over.
  static String _dateStable(String context) =>
      context.replaceFirst(RegExp(r' \(\d{1,2}:\d{2} [ap]m\)'), '');

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}\n[context truncated]';

  static String _num(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const List<String> _weekdays = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static String _longDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Compact date that still disambiguates the year.
  ///
  /// Omitting the year made dates a year apart render identically — a
  /// vaccination given on 1 Feb with its next dose due the following 1 Feb
  /// read as "given 1 Feb (next due 1 Feb)", and the model faithfully repeated
  /// the nonsense. Any date outside the current year now carries its year.
  static String _shortDate(DateTime d) {
    final String base = '${d.day} ${_months[d.month - 1].substring(0, 3)}';
    return d.year == DateTime.now().year ? base : '$base ${d.year}';
  }

  static String _timeOfDay(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }
}
