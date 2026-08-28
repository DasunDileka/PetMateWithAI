import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';
import 'feeding.dart' show dayKeyOf;

/// A prescribed medication course.
/// Stored at `users/{uid}/pets/{petId}/medicines/{id}`.
///
/// The document is the *plan* only. Individual administrations live in
/// [MedicineDose] records, mirroring the feeding schedule/record split so that
/// adherence can be measured rather than estimated.
class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.status = MedicineStatus.active,
    this.veterinarianId,
    this.veterinarianName,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Free text exactly as prescribed, e.g. "1 tablet (50 mg)". PetMate never
  /// computes or alters a dosage — it only stores what the owner entered.
  final String dosage;

  final MedicineFrequency frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final MedicineStatus status;
  final String? veterinarianId;
  final String? veterinarianName;
  final String? notes;
  final DateTime createdAt;

  bool get isActive {
    if (status != MedicineStatus.active) return false;
    final DateTime now = DateTime.now();
    if (now.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) {
      return false;
    }
    final DateTime? end = endDate;
    if (end == null) return true;
    return !now.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
  }

  /// Whole days remaining in the course, or null for an open-ended course.
  int? get daysRemaining {
    final DateTime? end = endDate;
    if (end == null) return null;
    final DateTime today = DateTime.now();
    final int diff = DateTime(end.year, end.month, end.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    return diff < 0 ? 0 : diff;
  }

  /// The times this medicine is due on [day], derived from [frequency].
  /// Returns empty for as-needed courses, which must never be auto-scheduled.
  List<DateTime> dueTimesOn(DateTime day) {
    if (!_coversDay(day)) return const <DateTime>[];

    if (frequency == MedicineFrequency.everyOtherDay) {
      final int elapsed = DateTime(day.year, day.month, day.day)
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays;
      if (elapsed % 2 != 0) return const <DateTime>[];
    }

    if (frequency == MedicineFrequency.weekly && day.weekday != startDate.weekday) {
      return const <DateTime>[];
    }

    return frequency.defaultHours
        .map((h) => DateTime(day.year, day.month, day.day, h))
        .toList(growable: false);
  }

  bool _coversDay(DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    final DateTime start =
        DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(start)) return false;
    final DateTime? end = endDate;
    if (end == null) return true;
    return !d.isAfter(DateTime(end.year, end.month, end.day));
  }

  factory Medicine.fromMap(String id, Map<String, dynamic> map) {
    return Medicine(
      id: id,
      name: readString(map['name'], fallback: 'Medicine'),
      dosage: readString(map['dosage']),
      frequency: readEnum(
        map['frequency'],
        MedicineFrequency.values,
        MedicineFrequency.onceDaily,
        (e) => e.name,
      ),
      startDate: readDate(map['startDate'], fallback: DateTime.now()),
      endDate: readDateOrNull(map['endDate']),
      status: readEnum(
        map['status'],
        MedicineStatus.values,
        MedicineStatus.active,
        (e) => e.name,
      ),
      veterinarianId: readStringOrNull(map['veterinarianId']),
      veterinarianName: readStringOrNull(map['veterinarianName']),
      notes: readStringOrNull(map['notes']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'name': name.trim(),
        'dosage': dosage.trim(),
        'frequency': frequency.name,
        'startDate': startDate,
        'endDate': endDate,
        'status': status.name,
        'veterinarianId': veterinarianId,
        'veterinarianName': veterinarianName?.trim(),
        'notes': notes?.trim(),
        'createdAt': createdAt,
      });

  Medicine copyWith({
    String? name,
    String? dosage,
    MedicineFrequency? frequency,
    DateTime? startDate,
    DateTime? endDate,
    MedicineStatus? status,
    String? veterinarianId,
    String? veterinarianName,
    String? notes,
    bool clearEndDate = false,
  }) {
    return Medicine(
      id: id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      status: status ?? this.status,
      veterinarianId: veterinarianId ?? this.veterinarianId,
      veterinarianName: veterinarianName ?? this.veterinarianName,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}

/// One administration of a [Medicine].
/// Stored at `users/{uid}/pets/{petId}/medicineDoses/{id}`.
class MedicineDose {
  const MedicineDose({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.dueAt,
    required this.status,
    this.recordedAt,
    this.notes,
  });

  final String id;
  final String medicineId;

  /// Denormalised so the history and calendar can render a dose without a
  /// second read of the parent medicine document.
  final String medicineName;

  final DateTime dueAt;
  final CareStatus status;
  final DateTime? recordedAt;
  final String? notes;

  factory MedicineDose.fromMap(String id, Map<String, dynamic> map) {
    return MedicineDose(
      id: id,
      medicineId: readString(map['medicineId']),
      medicineName: readString(map['medicineName'], fallback: 'Medicine'),
      dueAt: readDate(map['dueAt'], fallback: DateTime.now()),
      status: readEnum(
        map['status'],
        CareStatus.values,
        CareStatus.pending,
        (e) => e.name,
      ),
      recordedAt: readDateOrNull(map['recordedAt']),
      notes: readStringOrNull(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'medicineId': medicineId,
        'medicineName': medicineName,
        'dueAt': dueAt,
        'status': status.name,
        'recordedAt': recordedAt,
        'notes': notes?.trim(),
        'dayKey': dayKeyOf(dueAt),
      });

  MedicineDose copyWith({CareStatus? status, DateTime? recordedAt, String? notes}) {
    return MedicineDose(
      id: id,
      medicineId: medicineId,
      medicineName: medicineName,
      dueAt: dueAt,
      status: status ?? this.status,
      recordedAt: recordedAt ?? this.recordedAt,
      notes: notes ?? this.notes,
    );
  }
}
