import 'package:flutter/material.dart';

import 'appointment.dart';
import 'care_enums.dart';
import 'exercise.dart';
import 'feeding.dart';
import 'grooming.dart';
import 'medicine.dart';
import 'vaccination.dart';

/// A single row in the unified care history and the calendar.
///
/// The six care collections have genuinely different shapes, so rather than
/// forcing them into one Firestore schema they are projected into this common
/// view model at read time. That keeps each collection's queries efficient and
/// still gives the history and calendar one type to render.
class CareEvent {
  const CareEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.occurredAt,
    this.subtitle,
    this.status,
    this.detail,
    this.sourceId,
  });

  final String id;
  final CareType type;
  final String title;
  final DateTime occurredAt;
  final String? subtitle;
  final CareStatus? status;

  /// Longer secondary line, e.g. notes.
  final String? detail;

  final String? sourceId;

  Color get color => type.color;
  IconData get icon => type.icon;

  /// Local-time day bucket, used to group the history list and populate the
  /// calendar's per-day event map.
  DateTime get day =>
      DateTime(occurredAt.year, occurredAt.month, occurredAt.day);

  // ------------------------------------------------------------ projections

  factory CareEvent.fromFeeding(FeedingRecord r) => CareEvent(
        id: 'feeding_${r.id}',
        type: CareType.feeding,
        title: r.label ?? 'Feeding',
        occurredAt: r.completedAt ?? r.scheduledAt,
        subtitle: r.quantity != null && r.quantity! > 0
            ? '${_num(r.quantity!)} ${r.unit}${r.foodType == null ? '' : ' · ${r.foodType}'}'
            : r.foodType,
        status: r.status,
        detail: r.notes,
        sourceId: r.id,
      );

  factory CareEvent.fromExercise(ExerciseRecord r) => CareEvent(
        id: 'exercise_${r.id}',
        type: CareType.exercise,
        title: r.type.label,
        occurredAt: r.occurredAt,
        subtitle: r.distanceKm != null && r.distanceKm! > 0
            ? '${r.durationMinutes} min · ${r.distanceLabel}'
            : '${r.durationMinutes} min',
        status: CareStatus.completed,
        detail: r.notes,
        sourceId: r.id,
      );

  factory CareEvent.fromMedicineDose(MedicineDose d) => CareEvent(
        id: 'dose_${d.id}',
        type: CareType.medicine,
        title: d.medicineName,
        occurredAt: d.recordedAt ?? d.dueAt,
        subtitle: 'Dose ${d.status.label.toLowerCase()}',
        status: d.status,
        detail: d.notes,
        sourceId: d.medicineId,
      );

  factory CareEvent.fromVaccination(Vaccination v) => CareEvent(
        id: 'vaccination_${v.id}',
        type: CareType.vaccination,
        title: v.vaccineName,
        occurredAt: v.administeredAt,
        subtitle: v.veterinarianName ?? 'Administered',
        status: CareStatus.completed,
        detail: v.notes,
        sourceId: v.id,
      );

  /// Projects the *next due* dose of a vaccination as a forward-looking event
  /// so it appears on the calendar ahead of time.
  static CareEvent? upcomingVaccination(Vaccination v) {
    final DateTime? due = v.nextDueAt;
    if (due == null) return null;
    return CareEvent(
      id: 'vaccination_due_${v.id}',
      type: CareType.vaccination,
      title: '${v.vaccineName} due',
      occurredAt: due,
      subtitle: v.dueLabel,
      status: v.isOverdue ? CareStatus.missed : CareStatus.pending,
      sourceId: v.id,
    );
  }

  factory CareEvent.fromGrooming(GroomingRecord g) => CareEvent(
        id: 'grooming_${g.id}',
        type: CareType.grooming,
        title: g.type.label,
        occurredAt: g.lastCompletedAt ?? g.createdAt,
        subtitle: g.lastCompletedAt == null ? 'Not completed yet' : 'Completed',
        status: g.lastCompletedAt == null ? CareStatus.pending : CareStatus.completed,
        detail: g.notes,
        sourceId: g.id,
      );

  static CareEvent? upcomingGrooming(GroomingRecord g) {
    final DateTime? due = g.nextDueAt;
    if (due == null) return null;
    return CareEvent(
      id: 'grooming_due_${g.id}',
      type: CareType.grooming,
      title: '${g.type.label} due',
      occurredAt: due,
      subtitle: g.dueLabel,
      status: g.isOverdue ? CareStatus.missed : CareStatus.pending,
      sourceId: g.id,
    );
  }

  factory CareEvent.fromAppointment(Appointment a) => CareEvent(
        id: 'appointment_${a.id}',
        type: CareType.appointment,
        title: a.reason,
        occurredAt: a.scheduledAt,
        subtitle: a.veterinarianName ?? a.clinicName ?? 'Veterinary appointment',
        status: switch (a.status) {
          AppointmentStatus.completed => CareStatus.completed,
          AppointmentStatus.cancelled => CareStatus.skipped,
          AppointmentStatus.upcoming => CareStatus.pending,
        },
        detail: a.outcome ?? a.notes,
        sourceId: a.id,
      );

  static String _num(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Groups events into descending day buckets for a sectioned history list.
Map<DateTime, List<CareEvent>> groupByDay(List<CareEvent> events) {
  final Map<DateTime, List<CareEvent>> grouped = <DateTime, List<CareEvent>>{};
  for (final CareEvent e in events) {
    grouped.putIfAbsent(e.day, () => <CareEvent>[]).add(e);
  }
  for (final List<CareEvent> list in grouped.values) {
    list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }
  return grouped;
}
