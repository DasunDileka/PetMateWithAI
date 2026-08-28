import '../../core/utils/field_mapper.dart';

/// A vaccination the owner has recorded.
/// Stored at `users/{uid}/pets/{petId}/vaccinations/{id}`.
///
/// Every field here is owner-entered or vet-provided. PetMate deliberately
/// ships no vaccine catalogue and no default schedule: inventing a vaccination
/// requirement would be a medical claim, which the AI safety policy forbids.
class Vaccination {
  const Vaccination({
    required this.id,
    required this.vaccineName,
    required this.administeredAt,
    this.nextDueAt,
    this.veterinarianId,
    this.veterinarianName,
    this.batchNumber,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String vaccineName;
  final DateTime administeredAt;

  /// Next due date **as told to the owner by their vet**. Never derived.
  final DateTime? nextDueAt;

  final String? veterinarianId;
  final String? veterinarianName;
  final String? batchNumber;
  final String? notes;
  final DateTime createdAt;

  /// Days until the next dose is due. Negative when overdue, null when the
  /// owner did not record a next-due date.
  int? get daysUntilDue {
    final DateTime? due = nextDueAt;
    if (due == null) return null;
    final DateTime today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  bool get isOverdue => (daysUntilDue ?? 1) < 0;

  /// True when the next dose falls inside the reminder horizon.
  bool isDueWithin(int days) {
    final int? d = daysUntilDue;
    return d != null && d >= 0 && d <= days;
  }

  String get dueLabel {
    final int? d = daysUntilDue;
    if (d == null) return 'No next date recorded';
    if (d < 0) return 'Overdue by ${-d} day${d == -1 ? '' : 's'}';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    return 'Due in $d days';
  }

  factory Vaccination.fromMap(String id, Map<String, dynamic> map) {
    return Vaccination(
      id: id,
      vaccineName: readString(map['vaccineName'], fallback: 'Vaccination'),
      administeredAt: readDate(map['administeredAt'], fallback: DateTime.now()),
      nextDueAt: readDateOrNull(map['nextDueAt']),
      veterinarianId: readStringOrNull(map['veterinarianId']),
      veterinarianName: readStringOrNull(map['veterinarianName']),
      batchNumber: readStringOrNull(map['batchNumber']),
      notes: readStringOrNull(map['notes']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'vaccineName': vaccineName.trim(),
        'administeredAt': administeredAt,
        'nextDueAt': nextDueAt,
        'veterinarianId': veterinarianId,
        'veterinarianName': veterinarianName?.trim(),
        'batchNumber': batchNumber?.trim(),
        'notes': notes?.trim(),
        'createdAt': createdAt,
      });

  Vaccination copyWith({
    String? vaccineName,
    DateTime? administeredAt,
    DateTime? nextDueAt,
    String? veterinarianId,
    String? veterinarianName,
    String? batchNumber,
    String? notes,
    bool clearNextDue = false,
  }) {
    return Vaccination(
      id: id,
      vaccineName: vaccineName ?? this.vaccineName,
      administeredAt: administeredAt ?? this.administeredAt,
      nextDueAt: clearNextDue ? null : (nextDueAt ?? this.nextDueAt),
      veterinarianId: veterinarianId ?? this.veterinarianId,
      veterinarianName: veterinarianName ?? this.veterinarianName,
      batchNumber: batchNumber ?? this.batchNumber,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}
