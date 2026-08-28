import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';

/// A recurring feeding slot, e.g. "Morning — 200 g dry kibble at 07:30".
///
/// Stored at `users/{uid}/pets/{petId}/feedingSchedules/{id}`.
/// Schedules are the *plan*; [FeedingRecord] entries are the *actuals*. Keeping
/// them separate is what makes "12 of 14 scheduled feedings completed" a real
/// measurement rather than a guess.
class FeedingSchedule {
  const FeedingSchedule({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    this.foodType,
    this.quantity,
    this.unit = 'g',
    this.active = true,
    this.notes,
    required this.createdAt,
  });

  final String id;

  /// "Morning", "Evening", or anything the user types.
  final String label;

  final int hour;
  final int minute;

  final String? foodType;
  final double? quantity;
  final String unit;

  /// Inactive schedules stop generating reminders and stop counting towards
  /// completion statistics, but their history is preserved.
  final bool active;

  final String? notes;
  final DateTime createdAt;

  String get timeLabel {
    final int h12 = hour % 12 == 0 ? 12 : hour % 12;
    final String mm = minute.toString().padLeft(2, '0');
    final String period = hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $period';
  }

  String get portionLabel {
    if (quantity == null || quantity! <= 0) return foodType ?? 'Not specified';
    final String q = quantity! % 1 == 0
        ? quantity!.toStringAsFixed(0)
        : quantity!.toStringAsFixed(1);
    return foodType == null ? '$q $unit' : '$q $unit $foodType';
  }

  /// The moment this schedule is due on a given day.
  DateTime dueOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  factory FeedingSchedule.fromMap(String id, Map<String, dynamic> map) {
    return FeedingSchedule(
      id: id,
      label: readString(map['label'], fallback: 'Feeding'),
      hour: readInt(map['hour']).clamp(0, 23),
      minute: readInt(map['minute']).clamp(0, 59),
      foodType: readStringOrNull(map['foodType']),
      quantity: readDoubleOrNull(map['quantity']),
      unit: readString(map['unit'], fallback: 'g'),
      active: readBool(map['active'], fallback: true),
      notes: readStringOrNull(map['notes']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'label': label.trim(),
        'hour': hour,
        'minute': minute,
        'foodType': foodType?.trim(),
        'quantity': quantity,
        'unit': unit,
        'active': active,
        'notes': notes?.trim(),
        'createdAt': createdAt,
      });

  FeedingSchedule copyWith({
    String? label,
    int? hour,
    int? minute,
    String? foodType,
    double? quantity,
    String? unit,
    bool? active,
    String? notes,
  }) {
    return FeedingSchedule(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      foodType: foodType ?? this.foodType,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}

/// One actual feeding occurrence.
///
/// Stored at `users/{uid}/pets/{petId}/feedingRecords/{id}`.
/// A record is created lazily: the app only materialises a document once the
/// user marks a slot completed, skipped, or the slot lapses into `missed`.
class FeedingRecord {
  const FeedingRecord({
    required this.id,
    required this.scheduledAt,
    required this.status,
    this.scheduleId,
    this.label,
    this.completedAt,
    this.foodType,
    this.quantity,
    this.unit = 'g',
    this.notes,
  });

  final String id;

  /// When the feeding was *due*. Ordering and "missed" detection both key off
  /// this, so it is always written even for ad-hoc feedings.
  final DateTime scheduledAt;

  final CareStatus status;

  /// Null for an ad-hoc feeding that did not come from a schedule.
  final String? scheduleId;
  final String? label;

  final DateTime? completedAt;
  final String? foodType;
  final double? quantity;
  final String unit;
  final String? notes;

  bool get isCompleted => status == CareStatus.completed;

  factory FeedingRecord.fromMap(String id, Map<String, dynamic> map) {
    return FeedingRecord(
      id: id,
      scheduledAt: readDate(map['scheduledAt'], fallback: DateTime.now()),
      status: readEnum(
        map['status'],
        CareStatus.values,
        CareStatus.pending,
        (e) => e.name,
      ),
      scheduleId: readStringOrNull(map['scheduleId']),
      label: readStringOrNull(map['label']),
      completedAt: readDateOrNull(map['completedAt']),
      foodType: readStringOrNull(map['foodType']),
      quantity: readDoubleOrNull(map['quantity']),
      unit: readString(map['unit'], fallback: 'g'),
      notes: readStringOrNull(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'scheduledAt': scheduledAt,
        'status': status.name,
        'scheduleId': scheduleId,
        'label': label,
        'completedAt': completedAt,
        'foodType': foodType?.trim(),
        'quantity': quantity,
        'unit': unit,
        'notes': notes?.trim(),
        // Denormalised day key so "today's feedings" is a single equality
        // filter rather than a range query needing a composite index.
        'dayKey': dayKeyOf(scheduledAt),
      });

  FeedingRecord copyWith({
    CareStatus? status,
    DateTime? completedAt,
    String? foodType,
    double? quantity,
    String? unit,
    String? notes,
    bool clearCompletedAt = false,
  }) {
    return FeedingRecord(
      id: id,
      scheduledAt: scheduledAt,
      status: status ?? this.status,
      scheduleId: scheduleId,
      label: label,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      foodType: foodType ?? this.foodType,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
    );
  }
}

/// `yyyy-MM-dd` in local time. Shared by every care record that needs a cheap
/// "same day" filter.
String dayKeyOf(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';
