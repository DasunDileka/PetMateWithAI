import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';
import 'feeding.dart' show dayKeyOf;

/// A grooming task with its own cadence.
/// Stored at `users/{uid}/pets/{petId}/groomingRecords/{id}`.
///
/// One document per grooming *task* (not per occurrence): the document carries
/// the last completion and the next due date, which is what the dashboard,
/// calendar and reminders all read. Past completions are appended to the
/// unified medical/care history when a task is marked done.
class GroomingRecord {
  const GroomingRecord({
    required this.id,
    required this.type,
    this.lastCompletedAt,
    this.nextDueAt,
    this.intervalDays,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final GroomingType type;
  final DateTime? lastCompletedAt;
  final DateTime? nextDueAt;

  /// Owner-chosen cadence. Defaults to [GroomingType.defaultIntervalDays] when
  /// the owner does not set one.
  final int? intervalDays;

  final String? notes;
  final DateTime createdAt;

  int get effectiveIntervalDays => intervalDays ?? type.defaultIntervalDays;

  int? get daysUntilDue {
    final DateTime? due = nextDueAt;
    if (due == null) return null;
    final DateTime today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  bool get isOverdue => (daysUntilDue ?? 1) < 0;

  bool isDueWithin(int days) {
    final int? d = daysUntilDue;
    return d != null && d >= 0 && d <= days;
  }

  String get dueLabel {
    final int? d = daysUntilDue;
    if (d == null) return 'Not scheduled';
    if (d < 0) return 'Overdue by ${-d} day${d == -1 ? '' : 's'}';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    return 'Due in $d days';
  }

  /// Marks the task done at [when] and rolls the next due date forward by the
  /// configured cadence.
  GroomingRecord completedAt(DateTime when) {
    return copyWith(
      lastCompletedAt: when,
      nextDueAt: DateTime(when.year, when.month, when.day)
          .add(Duration(days: effectiveIntervalDays)),
    );
  }

  factory GroomingRecord.fromMap(String id, Map<String, dynamic> map) {
    return GroomingRecord(
      id: id,
      type: readEnum(
        map['type'],
        GroomingType.values,
        GroomingType.other,
        (e) => e.name,
      ),
      lastCompletedAt: readDateOrNull(map['lastCompletedAt']),
      nextDueAt: readDateOrNull(map['nextDueAt']),
      intervalDays: map['intervalDays'] == null ? null : readInt(map['intervalDays']),
      notes: readStringOrNull(map['notes']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'type': type.name,
        'lastCompletedAt': lastCompletedAt,
        'nextDueAt': nextDueAt,
        'intervalDays': intervalDays,
        'notes': notes?.trim(),
        'createdAt': createdAt,
        if (nextDueAt != null) 'dueDayKey': dayKeyOf(nextDueAt!),
      });

  GroomingRecord copyWith({
    GroomingType? type,
    DateTime? lastCompletedAt,
    DateTime? nextDueAt,
    int? intervalDays,
    String? notes,
  }) {
    return GroomingRecord(
      id: id,
      type: type ?? this.type,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      intervalDays: intervalDays ?? this.intervalDays,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}
