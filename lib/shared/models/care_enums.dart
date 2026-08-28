import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The six care domains PetMate tracks. Everything in the app — dashboard
/// tiles, calendar entries, unified history, notifications and AI context — is
/// keyed off this enum, so adding a seventh domain later is a localised change
/// rather than a cross-cutting one.
enum CareType {
  feeding,
  exercise,
  medicine,
  vaccination,
  grooming,
  appointment;

  String get label => switch (this) {
        CareType.feeding => 'Feeding',
        CareType.exercise => 'Exercise',
        CareType.medicine => 'Medicine',
        CareType.vaccination => 'Vaccination',
        CareType.grooming => 'Grooming',
        CareType.appointment => 'Vet Visit',
      };

  /// Used in headings and notification copy.
  String get emoji => switch (this) {
        CareType.feeding => '🍖',
        CareType.exercise => '🏃',
        CareType.medicine => '💊',
        CareType.vaccination => '💉',
        CareType.grooming => '🛁',
        CareType.appointment => '🩺',
      };

  IconData get icon => switch (this) {
        CareType.feeding => Icons.restaurant_rounded,
        CareType.exercise => Icons.directions_walk_rounded,
        CareType.medicine => Icons.medication_rounded,
        CareType.vaccination => Icons.vaccines_rounded,
        CareType.grooming => Icons.shower_rounded,
        CareType.appointment => Icons.local_hospital_rounded,
      };

  Color get color => switch (this) {
        CareType.feeding => AppColors.feeding,
        CareType.exercise => AppColors.exercise,
        CareType.medicine => AppColors.medicine,
        CareType.vaccination => AppColors.vaccination,
        CareType.grooming => AppColors.grooming,
        CareType.appointment => AppColors.vet,
      };

  /// Firestore subcollection this domain is stored in.
  String get collection => switch (this) {
        CareType.feeding => 'feedingRecords',
        CareType.exercise => 'exerciseRecords',
        CareType.medicine => 'medicines',
        CareType.vaccination => 'vaccinations',
        CareType.grooming => 'groomingRecords',
        CareType.appointment => 'appointments',
      };
}

/// Completion state shared by scheduled care items.
enum CareStatus {
  pending,
  completed,
  missed,
  skipped;

  String get label => switch (this) {
        CareStatus.pending => 'Pending',
        CareStatus.completed => 'Completed',
        CareStatus.missed => 'Missed',
        CareStatus.skipped => 'Skipped',
      };

  Color get color => switch (this) {
        CareStatus.pending => AppColors.warning,
        CareStatus.completed => AppColors.success,
        CareStatus.missed => AppColors.danger,
        CareStatus.skipped => AppColors.inkFaint,
      };

  IconData get icon => switch (this) {
        CareStatus.pending => Icons.schedule_rounded,
        CareStatus.completed => Icons.check_circle_rounded,
        CareStatus.missed => Icons.error_rounded,
        CareStatus.skipped => Icons.remove_circle_outline_rounded,
      };

  bool get isDone => this == CareStatus.completed;
}

enum PetSpecies {
  dog,
  cat,
  bird,
  rabbit,
  other;

  String get label => switch (this) {
        PetSpecies.dog => 'Dog',
        PetSpecies.cat => 'Cat',
        PetSpecies.bird => 'Bird',
        PetSpecies.rabbit => 'Rabbit',
        PetSpecies.other => 'Other',
      };

  String get emoji => switch (this) {
        PetSpecies.dog => '🐶',
        PetSpecies.cat => '🐱',
        PetSpecies.bird => '🐦',
        PetSpecies.rabbit => '🐰',
        PetSpecies.other => '🐾',
      };

  /// Typical adult weight band, used only to phrase AI context (never to make
  /// a clinical claim).
  ({double min, double max}) get typicalWeightKg => switch (this) {
        PetSpecies.dog => (min: 2, max: 70),
        PetSpecies.cat => (min: 2, max: 10),
        PetSpecies.bird => (min: 0.02, max: 2),
        PetSpecies.rabbit => (min: 1, max: 8),
        PetSpecies.other => (min: 0.02, max: 100),
      };
}

enum PetGender {
  male,
  female,
  unknown;

  String get label => switch (this) {
        PetGender.male => 'Male',
        PetGender.female => 'Female',
        PetGender.unknown => 'Not specified',
      };

  IconData get icon => switch (this) {
        PetGender.male => Icons.male_rounded,
        PetGender.female => Icons.female_rounded,
        PetGender.unknown => Icons.pets_rounded,
      };
}

enum ExerciseType {
  walk,
  run,
  play,
  training,
  other;

  String get label => switch (this) {
        ExerciseType.walk => 'Walk',
        ExerciseType.run => 'Run',
        ExerciseType.play => 'Play',
        ExerciseType.training => 'Training',
        ExerciseType.other => 'Other',
      };

  IconData get icon => switch (this) {
        ExerciseType.walk => Icons.directions_walk_rounded,
        ExerciseType.run => Icons.directions_run_rounded,
        ExerciseType.play => Icons.sports_baseball_rounded,
        ExerciseType.training => Icons.school_rounded,
        ExerciseType.other => Icons.more_horiz_rounded,
      };

  /// Rough intensity weighting used by the local trend analytics so that ten
  /// minutes of running is not treated as equal to ten minutes of gentle play.
  double get intensityFactor => switch (this) {
        ExerciseType.walk => 1.0,
        ExerciseType.run => 1.6,
        ExerciseType.play => 1.2,
        ExerciseType.training => 0.9,
        ExerciseType.other => 1.0,
      };
}

enum GroomingType {
  bath,
  nailTrim,
  hairTrim,
  teethCleaning,
  earCleaning,
  other;

  String get label => switch (this) {
        GroomingType.bath => 'Bath',
        GroomingType.nailTrim => 'Nail Trimming',
        GroomingType.hairTrim => 'Hair Trimming',
        GroomingType.teethCleaning => 'Teeth Cleaning',
        GroomingType.earCleaning => 'Ear Cleaning',
        GroomingType.other => 'Other',
      };

  IconData get icon => switch (this) {
        GroomingType.bath => Icons.shower_rounded,
        GroomingType.nailTrim => Icons.content_cut_rounded,
        GroomingType.hairTrim => Icons.cut_rounded,
        GroomingType.teethCleaning => Icons.cleaning_services_rounded,
        GroomingType.earCleaning => Icons.hearing_rounded,
        GroomingType.other => Icons.spa_rounded,
      };

  /// Default cadence suggested when the user adds a grooming task. The user can
  /// always override it — this is a UI convenience, not a clinical schedule.
  int get defaultIntervalDays => switch (this) {
        GroomingType.bath => 30,
        GroomingType.nailTrim => 21,
        GroomingType.hairTrim => 60,
        GroomingType.teethCleaning => 7,
        GroomingType.earCleaning => 14,
        GroomingType.other => 30,
      };
}

enum AppointmentStatus {
  upcoming,
  completed,
  cancelled;

  String get label => switch (this) {
        AppointmentStatus.upcoming => 'Upcoming',
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        AppointmentStatus.upcoming => AppColors.info,
        AppointmentStatus.completed => AppColors.success,
        AppointmentStatus.cancelled => AppColors.inkFaint,
      };
}

enum MedicineStatus {
  active,
  completed,
  paused;

  String get label => switch (this) {
        MedicineStatus.active => 'Active',
        MedicineStatus.completed => 'Completed',
        MedicineStatus.paused => 'Paused',
      };

  Color get color => switch (this) {
        MedicineStatus.active => AppColors.success,
        MedicineStatus.completed => AppColors.inkFaint,
        MedicineStatus.paused => AppColors.warning,
      };
}

/// How often a medicine is administered. Stored as an enum rather than free
/// text so reminders and adherence statistics can be computed reliably.
enum MedicineFrequency {
  onceDaily,
  twiceDaily,
  threeTimesDaily,
  everyOtherDay,
  weekly,
  asNeeded;

  String get label => switch (this) {
        MedicineFrequency.onceDaily => 'Once daily',
        MedicineFrequency.twiceDaily => 'Twice daily',
        MedicineFrequency.threeTimesDaily => 'Three times daily',
        MedicineFrequency.everyOtherDay => 'Every other day',
        MedicineFrequency.weekly => 'Weekly',
        MedicineFrequency.asNeeded => 'As needed',
      };

  /// Doses expected in a 24-hour period. `asNeeded` returns 0 because it must
  /// never count against an adherence percentage.
  int get dosesPerDay => switch (this) {
        MedicineFrequency.onceDaily => 1,
        MedicineFrequency.twiceDaily => 2,
        MedicineFrequency.threeTimesDaily => 3,
        MedicineFrequency.everyOtherDay => 0,
        MedicineFrequency.weekly => 0,
        MedicineFrequency.asNeeded => 0,
      };

  /// Default administration times seeded into the reminder scheduler.
  List<int> get defaultHours => switch (this) {
        MedicineFrequency.onceDaily => const [8],
        MedicineFrequency.twiceDaily => const [8, 20],
        MedicineFrequency.threeTimesDaily => const [8, 14, 20],
        MedicineFrequency.everyOtherDay => const [8],
        MedicineFrequency.weekly => const [8],
        MedicineFrequency.asNeeded => const [],
      };
}
