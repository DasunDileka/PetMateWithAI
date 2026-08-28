import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';
import 'feeding.dart' show dayKeyOf;

/// A veterinary appointment.
/// Stored at `users/{uid}/pets/{petId}/appointments/{id}`.
class Appointment {
  const Appointment({
    required this.id,
    required this.scheduledAt,
    required this.reason,
    this.veterinarianId,
    this.veterinarianName,
    this.clinicName,
    this.status = AppointmentStatus.upcoming,
    this.notes,
    this.outcome,
    required this.createdAt,
  });

  final String id;
  final DateTime scheduledAt;
  final String reason;

  final String? veterinarianId;

  /// Denormalised vet details so the appointment list renders in one read and
  /// still reads correctly if the vet contact is later deleted.
  final String? veterinarianName;
  final String? clinicName;

  final AppointmentStatus status;
  final String? notes;

  /// Filled in after the visit; feeds the unified medical history.
  final String? outcome;

  final DateTime createdAt;

  bool get isUpcoming =>
      status == AppointmentStatus.upcoming && scheduledAt.isAfter(DateTime.now());

  /// True when the appointment time has passed but the owner has not yet
  /// marked it completed or cancelled — the UI prompts them to resolve it.
  bool get isAwaitingOutcome =>
      status == AppointmentStatus.upcoming && !scheduledAt.isAfter(DateTime.now());

  int get daysUntil {
    final DateTime now = DateTime.now();
    return DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  String get whenLabel {
    final int d = daysUntil;
    final String time = _timeLabel();
    if (d == 0) return 'Today at $time';
    if (d == 1) return 'Tomorrow at $time';
    if (d == -1) return 'Yesterday at $time';
    if (d < 0) return '${-d} days ago';
    return 'In $d days at $time';
  }

  String _timeLabel() {
    final int h = scheduledAt.hour;
    final int h12 = h % 12 == 0 ? 12 : h % 12;
    final String mm = scheduledAt.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${h < 12 ? 'AM' : 'PM'}';
  }

  factory Appointment.fromMap(String id, Map<String, dynamic> map) {
    return Appointment(
      id: id,
      scheduledAt: readDate(map['scheduledAt'], fallback: DateTime.now()),
      reason: readString(map['reason'], fallback: 'Consultation'),
      veterinarianId: readStringOrNull(map['veterinarianId']),
      veterinarianName: readStringOrNull(map['veterinarianName']),
      clinicName: readStringOrNull(map['clinicName']),
      status: readEnum(
        map['status'],
        AppointmentStatus.values,
        AppointmentStatus.upcoming,
        (e) => e.name,
      ),
      notes: readStringOrNull(map['notes']),
      outcome: readStringOrNull(map['outcome']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'scheduledAt': scheduledAt,
        'reason': reason.trim(),
        'veterinarianId': veterinarianId,
        'veterinarianName': veterinarianName?.trim(),
        'clinicName': clinicName?.trim(),
        'status': status.name,
        'notes': notes?.trim(),
        'outcome': outcome?.trim(),
        'createdAt': createdAt,
        'dayKey': dayKeyOf(scheduledAt),
      });

  Appointment copyWith({
    DateTime? scheduledAt,
    String? reason,
    String? veterinarianId,
    String? veterinarianName,
    String? clinicName,
    AppointmentStatus? status,
    String? notes,
    String? outcome,
  }) {
    return Appointment(
      id: id,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      reason: reason ?? this.reason,
      veterinarianId: veterinarianId ?? this.veterinarianId,
      veterinarianName: veterinarianName ?? this.veterinarianName,
      clinicName: clinicName ?? this.clinicName,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      outcome: outcome ?? this.outcome,
      createdAt: createdAt,
    );
  }
}

/// One entry in the unified medical history.
/// Stored at `users/{uid}/pets/{petId}/medicalHistory/{id}`.
///
/// Written by the app whenever a clinically relevant event is recorded (a vet
/// visit outcome, a vaccination, a completed medicine course, an owner
/// observation), giving a single chronological clinical record without having
/// to fan out reads across six collections.
class MedicalHistoryEntry {
  const MedicalHistoryEntry({
    required this.id,
    required this.title,
    required this.occurredAt,
    required this.category,
    this.description,
    this.veterinarianName,
    this.sourceCollection,
    this.sourceId,
    required this.createdAt,
  });

  final String id;
  final String title;
  final DateTime occurredAt;

  /// Which care domain produced the entry, or `observation` for owner notes.
  final String category;

  final String? description;
  final String? veterinarianName;

  /// Back-reference to the originating record so the UI can deep-link.
  final String? sourceCollection;
  final String? sourceId;

  final DateTime createdAt;

  CareType? get careType {
    for (final CareType t in CareType.values) {
      if (t.name == category) return t;
    }
    return null;
  }

  factory MedicalHistoryEntry.fromMap(String id, Map<String, dynamic> map) {
    return MedicalHistoryEntry(
      id: id,
      title: readString(map['title'], fallback: 'Record'),
      occurredAt: readDate(map['occurredAt'], fallback: DateTime.now()),
      category: readString(map['category'], fallback: 'observation'),
      description: readStringOrNull(map['description']),
      veterinarianName: readStringOrNull(map['veterinarianName']),
      sourceCollection: readStringOrNull(map['sourceCollection']),
      sourceId: readStringOrNull(map['sourceId']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'title': title.trim(),
        'occurredAt': occurredAt,
        'category': category,
        'description': description?.trim(),
        'veterinarianName': veterinarianName?.trim(),
        'sourceCollection': sourceCollection,
        'sourceId': sourceId,
        'createdAt': createdAt,
      });
}
