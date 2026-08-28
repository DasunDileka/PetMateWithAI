import 'dart:math' as math;

import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/exercise.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';

/// Deterministic, on-device analysis of a pet's care record.
///
/// This layer exists so that PetMate's "intelligence" is not wholly dependent
/// on a language model. Every number the AI ever states — completion rates,
/// averages, trend direction, anomaly flags — is computed here first and then
/// handed to the model as fact. The model's job is to *explain* the statistics
/// in natural language, never to invent them. That separation is what keeps
/// the assistant's claims verifiable and reproducible, and it means the core
/// insight features still work when the network or the AI provider is down.
///
/// Pure Dart, no I/O, no Firebase: directly unit-testable.
class CareAnalytics {
  const CareAnalytics._();

  /// Days of history used as the analysis window.
  static const int defaultWindowDays = 14;

  /// Days at the end of the window treated as "recent" when comparing against
  /// the earlier baseline.
  static const int recentWindowDays = 3;

  // ---------------------------------------------------------------- series

  /// Total exercise minutes per day, oldest first, with zero-filled gaps.
  ///
  /// Zero-filling matters: a day with no record is a day with no exercise, and
  /// silently dropping it would bias every average upward.
  static List<DailyMetric> exerciseSeries(
    List<ExerciseRecord> records, {
    int days = defaultWindowDays,
    DateTime? now,
  }) {
    final DateTime today = _startOfDay(now ?? DateTime.now());
    final Map<String, double> totals = <String, double>{};

    for (final ExerciseRecord r in records) {
      final DateTime day = _startOfDay(r.occurredAt);
      if (day.isAfter(today)) continue;
      if (today.difference(day).inDays >= days) continue;
      totals.update(
        dayKeyOf(day),
        (v) => v + r.durationMinutes,
        ifAbsent: () => r.durationMinutes.toDouble(),
      );
    }

    return List<DailyMetric>.generate(days, (i) {
      final DateTime day = today.subtract(Duration(days: days - 1 - i));
      return DailyMetric(day: day, value: totals[dayKeyOf(day)] ?? 0);
    });
  }

  /// Intensity-weighted exercise per day. Used for anomaly detection so a
  /// switch from running to gentle play registers as a change in activity.
  static List<DailyMetric> exerciseIntensitySeries(
    List<ExerciseRecord> records, {
    int days = defaultWindowDays,
    DateTime? now,
  }) {
    final DateTime today = _startOfDay(now ?? DateTime.now());
    final Map<String, double> totals = <String, double>{};

    for (final ExerciseRecord r in records) {
      final DateTime day = _startOfDay(r.occurredAt);
      if (day.isAfter(today) || today.difference(day).inDays >= days) continue;
      totals.update(
        dayKeyOf(day),
        (v) => v + r.intensityMinutes,
        ifAbsent: () => r.intensityMinutes,
      );
    }

    return List<DailyMetric>.generate(days, (i) {
      final DateTime day = today.subtract(Duration(days: days - 1 - i));
      return DailyMetric(day: day, value: totals[dayKeyOf(day)] ?? 0);
    });
  }

  // ----------------------------------------------------------------- trend

  /// Least-squares trend over a daily series.
  static TrendResult trend(List<DailyMetric> series) {
    final List<double> values = series.map((e) => e.value).toList();
    if (values.length < 4) {
      return TrendResult(
        series: series,
        slopePerDay: 0,
        mean: values.isEmpty ? 0 : _mean(values),
        stdDev: 0,
        direction: TrendDirection.insufficientData,
        changePercent: 0,
      );
    }

    final double mean = _mean(values);
    final double stdDev = _stdDev(values, mean);
    final double slope = _slope(values);

    // Compare the tail of the window against everything before it. A slope
    // alone can be dominated by one outlier day, so the percentage change is
    // computed from window means instead.
    final int recentCount = math.min(recentWindowDays, values.length ~/ 2);
    final List<double> recent = values.sublist(values.length - recentCount);
    final List<double> baseline = values.sublist(0, values.length - recentCount);

    final double recentMean = _mean(recent);
    final double baselineMean = _mean(baseline);

    final double changePercent = baselineMean <= 0
        ? (recentMean > 0 ? 100 : 0)
        : ((recentMean - baselineMean) / baselineMean) * 100;

    // A 15% band keeps normal day-to-day variation from being reported as a
    // trend. Below that the honest answer is "stable".
    final TrendDirection direction;
    if (changePercent.abs() < 15) {
      direction = TrendDirection.stable;
    } else if (changePercent > 0) {
      direction = TrendDirection.rising;
    } else {
      direction = TrendDirection.falling;
    }

    return TrendResult(
      series: series,
      slopePerDay: slope,
      mean: mean,
      stdDev: stdDev,
      direction: direction,
      changePercent: changePercent,
    );
  }

  // ------------------------------------------------------- completion rates

  /// Share of scheduled feedings actually completed over the last [days].
  ///
  /// The denominator is derived from active schedules (plan), not from the
  /// records that happen to exist, so feedings the owner never logged still
  /// count as missed.
  static CompletionStat feedingCompletion(
    List<FeedingSchedule> schedules,
    List<FeedingRecord> records, {
    int days = 7,
    DateTime? now,
  }) {
    final DateTime today = _startOfDay(now ?? DateTime.now());
    final DateTime windowStart = today.subtract(Duration(days: days - 1));
    final List<FeedingSchedule> active =
        schedules.where((s) => s.active).toList(growable: false);

    if (active.isEmpty) {
      // With no schedule there is no plan to measure against; fall back to
      // counting ad-hoc records so the figure is still meaningful.
      final List<FeedingRecord> inWindow = records
          .where((r) => !_startOfDay(r.scheduledAt).isBefore(windowStart))
          .toList(growable: false);
      final int done = inWindow.where((r) => r.isCompleted).length;
      return CompletionStat(
        completed: done,
        expected: inWindow.length,
        hasSchedule: false,
      );
    }

    int expected = 0;
    final DateTime nowTs = now ?? DateTime.now();

    for (int i = 0; i < days; i++) {
      final DateTime day = windowStart.add(Duration(days: i));
      for (final FeedingSchedule s in active) {
        // Only count slots that were created before the day and are already
        // due — a schedule added this afternoon should not make this morning
        // look like a miss.
        if (_startOfDay(s.createdAt).isAfter(day)) continue;
        if (s.dueOn(day).isAfter(nowTs)) continue;
        expected++;
      }
    }

    final int completed = records
        .where((r) =>
            r.isCompleted &&
            !_startOfDay(r.scheduledAt).isBefore(windowStart) &&
            !_startOfDay(r.scheduledAt).isAfter(today))
        .length;

    return CompletionStat(
      completed: math.min(completed, expected),
      expected: expected,
      hasSchedule: true,
    );
  }

  /// Share of due medicine doses recorded as taken over the last [days].
  static CompletionStat medicationAdherence(
    List<Medicine> medicines,
    List<MedicineDose> doses, {
    int days = 7,
    DateTime? now,
  }) {
    final DateTime nowTs = now ?? DateTime.now();
    final DateTime today = _startOfDay(nowTs);
    final DateTime windowStart = today.subtract(Duration(days: days - 1));

    int expected = 0;
    for (int i = 0; i < days; i++) {
      final DateTime day = windowStart.add(Duration(days: i));
      for (final Medicine m in medicines) {
        expected += m
            .dueTimesOn(day)
            .where((t) => !t.isAfter(nowTs))
            .length;
      }
    }

    final int taken = doses
        .where((d) =>
            d.status == CareStatus.completed &&
            !_startOfDay(d.dueAt).isBefore(windowStart) &&
            !d.dueAt.isAfter(nowTs))
        .length;

    return CompletionStat(
      completed: math.min(taken, expected),
      expected: expected,
      hasSchedule: medicines.isNotEmpty,
    );
  }

  // ------------------------------------------------------ anomaly detection

  /// Flags unusual care patterns.
  ///
  /// Every finding is phrased as an observation about *recorded data*. None of
  /// them asserts a cause, a diagnosis, or a health status — the app cannot
  /// know any of those, and claiming otherwise would be unsafe.
  static List<CareAnomaly> detectAnomalies({
    required Pet pet,
    required List<ExerciseRecord> exercise,
    required List<FeedingSchedule> feedingSchedules,
    required List<FeedingRecord> feedingRecords,
    required List<Medicine> medicines,
    required List<MedicineDose> doses,
    DateTime? now,
  }) {
    final DateTime nowTs = now ?? DateTime.now();
    final List<CareAnomaly> found = <CareAnomaly>[];

    // -- 1. Activity materially below this pet's own baseline ---------------
    final List<DailyMetric> series =
        exerciseIntensitySeries(exercise, now: nowTs);
    final TrendResult t = trend(series);

    final int recentCount = math.min(recentWindowDays, series.length ~/ 2);
    if (recentCount > 0 && series.length >= 8) {
      final List<double> values = series.map((e) => e.value).toList();
      final List<double> baseline = values.sublist(0, values.length - recentCount);
      final double baselineMean = _mean(baseline);
      final double baselineSd = _stdDev(baseline, baselineMean);
      final double recentMean = _mean(values.sublist(values.length - recentCount));

      // Require a real baseline before calling anything unusual: a pet with
      // almost no recorded activity has no "normal" to deviate from.
      if (baselineMean >= 8) {
        final double z =
            baselineSd < 1 ? 0 : (recentMean - baselineMean) / baselineSd;
        final double dropPercent =
            ((baselineMean - recentMean) / baselineMean) * 100;

        if (dropPercent >= 40 || z <= -1.5) {
          found.add(CareAnomaly(
            type: CareType.exercise,
            severity: dropPercent >= 65
                ? AnomalySeverity.watch
                : AnomalySeverity.notice,
            title: 'Activity lower than usual',
            description:
                '${pet.name}\'s recorded activity over the last $recentCount days '
                'averages ${recentMean.round()} weighted minutes per day, compared with '
                '${baselineMean.round()} earlier in the period '
                '(${dropPercent.round()}% lower). This is a change in the recorded '
                'data only. Consider monitoring ${pet.name}, and contact a '
                'veterinarian if the change continues or comes with other symptoms.',
            confidence: _confidenceFrom(dropPercent, z),
          ));
        }
      }
    }

    // -- 2. No activity recorded for consecutive days -----------------------
    final List<DailyMetric> raw = exerciseSeries(exercise, now: nowTs);
    int trailingZeros = 0;
    for (int i = raw.length - 1; i >= 0; i--) {
      if (raw[i].value > 0) break;
      trailingZeros++;
    }
    final bool everActive = raw.any((d) => d.value > 0);
    if (everActive && trailingZeros >= 3) {
      found.add(CareAnomaly(
        type: CareType.exercise,
        severity: AnomalySeverity.notice,
        title: 'No exercise recorded recently',
        description:
            'No exercise has been recorded for ${pet.name} in the last '
            '$trailingZeros days. If ${pet.name} has been active but you have not '
            'logged it, adding the sessions will keep the insights accurate.',
        confidence: 0.9,
      ));
    }

    // -- 3. Repeated missed feedings ---------------------------------------
    final DateTime threeDaysAgo = _startOfDay(nowTs).subtract(const Duration(days: 2));
    final int recentMissedFeedings = feedingRecords
        .where((r) =>
            r.status == CareStatus.missed &&
            !_startOfDay(r.scheduledAt).isBefore(threeDaysAgo))
        .length;

    if (recentMissedFeedings >= 2) {
      found.add(CareAnomaly(
        type: CareType.feeding,
        severity: AnomalySeverity.watch,
        title: 'Repeated missed feedings',
        description:
            '$recentMissedFeedings scheduled feedings have been marked as missed in '
            'the last three days. If ${pet.name} is refusing food rather than the '
            'feeding simply not being logged, that is worth raising with a '
            'veterinarian.',
        confidence: 0.85,
      ));
    }

    // -- 4. Repeated missed medication -------------------------------------
    final DateTime fiveDaysAgo = _startOfDay(nowTs).subtract(const Duration(days: 4));
    final int missedDoses = doses
        .where((d) =>
            d.status == CareStatus.missed &&
            !_startOfDay(d.dueAt).isBefore(fiveDaysAgo))
        .length;

    if (missedDoses >= 2) {
      found.add(CareAnomaly(
        type: CareType.medicine,
        severity: AnomalySeverity.watch,
        title: 'Missed medication doses',
        description:
            '$missedDoses medication doses have been recorded as missed in the last '
            'five days. Ask the prescribing veterinarian how to proceed — PetMate '
            'cannot advise on changing a dose or catching one up.',
        confidence: 0.95,
      ));
    }

    // Most significant first, so the dashboard shows the one that matters.
    found.sort((a, b) {
      final int bySeverity = b.severity.index.compareTo(a.severity.index);
      return bySeverity != 0
          ? bySeverity
          : b.confidence.compareTo(a.confidence);
    });

    // Trend is reported separately by the UI; the variable is retained here to
    // keep the exercise branch readable.
    assert(t.series.isNotEmpty || exercise.isEmpty);

    return found;
  }

  // -------------------------------------------------------------- snapshot

  /// Everything the dashboard and the AI context builder need about *today*,
  /// computed once so both read identical numbers.
  static TodaySnapshot today({
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
    final DateTime today = _startOfDay(nowTs);
    final String key = dayKeyOf(today);

    final List<FeedingRecord> todayFeedings = feedingRecords
        .where((r) => dayKeyOf(r.scheduledAt) == key)
        .toList(growable: false);

    final List<FeedingSchedule> activeSchedules =
        feedingSchedules.where((s) => s.active).toList(growable: false);

    final int feedingsDone = todayFeedings.where((r) => r.isCompleted).length;

    final int exerciseMinutes = exercise
        .where((r) => dayKeyOf(r.occurredAt) == key)
        .fold<int>(0, (sum, r) => sum + r.durationMinutes);

    final List<DateTime> dueDoses = <DateTime>[];
    for (final Medicine m in medicines.where((m) => m.isActive)) {
      dueDoses.addAll(m.dueTimesOn(today));
    }
    final int dosesTaken = doses
        .where((d) => dayKeyOf(d.dueAt) == key && d.status == CareStatus.completed)
        .length;

    final Vaccination? nextVaccination = _earliestBy<Vaccination>(
      vaccinations.where((v) => (v.daysUntilDue ?? -999) >= 0),
      (v) => v.nextDueAt!,
    );

    final GroomingRecord? nextGrooming = _earliestBy<GroomingRecord>(
      grooming.where((g) => g.nextDueAt != null),
      (g) => g.nextDueAt!,
    );

    final Appointment? nextAppointment = _earliestBy<Appointment>(
      appointments.where((a) =>
          a.status == AppointmentStatus.upcoming && a.scheduledAt.isAfter(nowTs)),
      (a) => a.scheduledAt,
    );

    return TodaySnapshot(
      date: today,
      feedingsCompleted: feedingsDone,
      feedingsScheduled: activeSchedules.length,
      pendingFeedings: activeSchedules
          .where((s) => !todayFeedings.any(
              (r) => r.scheduleId == s.id && r.status != CareStatus.pending))
          .toList(growable: false),
      exerciseMinutes: exerciseMinutes,
      dosesDue: dueDoses.length,
      dosesTaken: dosesTaken,
      nextVaccination: nextVaccination,
      nextGrooming: nextGrooming,
      nextAppointment: nextAppointment,
    );
  }

  // ----------------------------------------------------------------- maths

  static double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  static double _stdDev(List<double> v, double mean) {
    if (v.length < 2) return 0;
    final double sumSq =
        v.fold<double>(0, (acc, x) => acc + math.pow(x - mean, 2).toDouble());
    return math.sqrt(sumSq / (v.length - 1));
  }

  /// Least-squares slope against day index.
  static double _slope(List<double> y) {
    final int n = y.length;
    if (n < 2) return 0;
    final double meanX = (n - 1) / 2.0;
    final double meanY = _mean(y);
    double num = 0;
    double den = 0;
    for (int i = 0; i < n; i++) {
      num += (i - meanX) * (y[i] - meanY);
      den += math.pow(i - meanX, 2).toDouble();
    }
    return den == 0 ? 0 : num / den;
  }

  static double _confidenceFrom(double dropPercent, double z) {
    final double fromDrop = (dropPercent / 100).clamp(0.0, 1.0);
    final double fromZ = (z.abs() / 3).clamp(0.0, 1.0);
    return ((fromDrop * 0.6) + (fromZ * 0.4)).clamp(0.3, 0.95);
  }

  static DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static T? _earliestBy<T>(Iterable<T> items, DateTime Function(T) keyOf) {
    T? best;
    DateTime? bestKey;
    for (final T item in items) {
      final DateTime k = keyOf(item);
      if (bestKey == null || k.isBefore(bestKey)) {
        best = item;
        bestKey = k;
      }
    }
    return best;
  }
}

// ------------------------------------------------------------------ results

class DailyMetric {
  const DailyMetric({required this.day, required this.value});
  final DateTime day;
  final double value;

  /// Single-letter weekday label for compact chart axes.
  String get shortWeekday =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];

  String get weekdayLabel =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1];
}

enum TrendDirection {
  rising,
  stable,
  falling,
  insufficientData;

  String get label => switch (this) {
        TrendDirection.rising => 'Increasing',
        TrendDirection.stable => 'Stable',
        TrendDirection.falling => 'Decreasing',
        TrendDirection.insufficientData => 'Not enough data',
      };
}

class TrendResult {
  const TrendResult({
    required this.series,
    required this.slopePerDay,
    required this.mean,
    required this.stdDev,
    required this.direction,
    required this.changePercent,
  });

  final List<DailyMetric> series;
  final double slopePerDay;
  final double mean;
  final double stdDev;
  final TrendDirection direction;
  final double changePercent;

  bool get hasData => series.any((d) => d.value > 0);

  /// Caption for the compact stat tiles.
  ///
  /// [direction] on its own reads "Stable" for a pet with no recorded activity
  /// whatsoever — a zero-filled series has no variation to detect — which
  /// claims more than the data supports.
  String get shortLabel => hasData ? direction.label : 'No data';

  double get maxValue =>
      series.isEmpty ? 0 : series.map((e) => e.value).reduce(math.max);

  /// Plain-language summary used both in the UI and as a fact handed to the AI.
  String describe(String petName) {
    if (!hasData) return 'No exercise has been recorded for $petName yet.';
    return switch (direction) {
      TrendDirection.insufficientData =>
        'There is not yet enough recorded history to describe a trend for $petName.',
      TrendDirection.stable =>
        '$petName\'s recorded activity has been broadly stable, averaging '
            '${mean.round()} minutes per day.',
      TrendDirection.rising =>
        '$petName\'s recorded activity has increased by about '
            '${changePercent.abs().round()}% recently, averaging '
            '${mean.round()} minutes per day over the period.',
      TrendDirection.falling =>
        '$petName\'s recorded activity has decreased by about '
            '${changePercent.abs().round()}% recently, averaging '
            '${mean.round()} minutes per day over the period.',
    };
  }
}

class CompletionStat {
  const CompletionStat({
    required this.completed,
    required this.expected,
    required this.hasSchedule,
  });

  final int completed;
  final int expected;
  final bool hasSchedule;

  bool get hasData => expected > 0;
  int get missed => expected - completed;

  /// 0–100. Returns 0 when nothing was expected, and callers should check
  /// [hasData] before presenting it as a percentage.
  double get percent => expected == 0 ? 0 : (completed / expected) * 100;

  String get label => hasData ? '$completed of $expected' : 'No data';
}

enum AnomalySeverity {
  notice,
  watch;

  String get label => switch (this) {
        AnomalySeverity.notice => 'Notice',
        AnomalySeverity.watch => 'Worth watching',
      };
}

class CareAnomaly {
  const CareAnomaly({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.confidence,
  });

  final CareType type;
  final AnomalySeverity severity;
  final String title;
  final String description;

  /// 0–1, derived from effect size. Displayed so the user can weigh the signal
  /// rather than treating every flag as equally certain.
  final double confidence;
}

class TodaySnapshot {
  const TodaySnapshot({
    required this.date,
    required this.feedingsCompleted,
    required this.feedingsScheduled,
    required this.pendingFeedings,
    required this.exerciseMinutes,
    required this.dosesDue,
    required this.dosesTaken,
    this.nextVaccination,
    this.nextGrooming,
    this.nextAppointment,
  });

  final DateTime date;
  final int feedingsCompleted;
  final int feedingsScheduled;
  final List<FeedingSchedule> pendingFeedings;
  final int exerciseMinutes;
  final int dosesDue;
  final int dosesTaken;
  final Vaccination? nextVaccination;
  final GroomingRecord? nextGrooming;
  final Appointment? nextAppointment;

  bool get allFeedingsDone =>
      feedingsScheduled > 0 && feedingsCompleted >= feedingsScheduled;

  bool get hasExercise => exerciseMinutes > 0;

  bool get medicationOutstanding => dosesTaken < dosesDue;
}
