import 'dart:math' as math;

import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';
import 'feeding.dart' show dayKeyOf;

/// A single GPS sample captured during a tracked walk.
///
/// Recorded through the device location provider (the Android emulator's
/// mocked GPS during marking), which is what evidences the geolocation element
/// of LO2 without requiring any physical hardware.
class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  factory TrackPoint.fromMap(Map<String, dynamic> map) => TrackPoint(
        latitude: readDouble(map['lat']),
        longitude: readDouble(map['lng']),
        recordedAt: readDate(map['t'], fallback: DateTime.now()),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'lat': latitude,
        'lng': longitude,
        't': recordedAt,
      };
}

/// One completed exercise session.
/// Stored at `users/{uid}/pets/{petId}/exerciseRecords/{id}`.
class ExerciseRecord {
  const ExerciseRecord({
    required this.id,
    required this.type,
    required this.durationMinutes,
    required this.occurredAt,
    this.distanceKm,
    this.notes,
    this.route = const <TrackPoint>[],
  });

  final String id;
  final ExerciseType type;
  final int durationMinutes;
  final DateTime occurredAt;

  /// Present only for GPS-tracked sessions.
  final double? distanceKm;

  final String? notes;
  final List<TrackPoint> route;

  bool get wasTracked => route.length > 1;

  /// Duration weighted by activity intensity. The trend engine uses this so a
  /// 20-minute run is not scored identically to 20 minutes of gentle play.
  double get intensityMinutes => durationMinutes * type.intensityFactor;

  String get distanceLabel {
    final double? d = distanceKm;
    if (d == null || d <= 0) return '—';
    return d < 1
        ? '${(d * 1000).round()} m'
        : '${d.toStringAsFixed(2)} km';
  }

  factory ExerciseRecord.fromMap(String id, Map<String, dynamic> map) {
    final dynamic rawRoute = map['route'];
    return ExerciseRecord(
      id: id,
      type: readEnum(
        map['type'],
        ExerciseType.values,
        ExerciseType.walk,
        (e) => e.name,
      ),
      durationMinutes: readInt(map['durationMinutes']).clamp(0, 24 * 60),
      occurredAt: readDate(map['occurredAt'], fallback: DateTime.now()),
      distanceKm: readDoubleOrNull(map['distanceKm']),
      notes: readStringOrNull(map['notes']),
      route: rawRoute is List
          ? rawRoute
              .whereType<Map>()
              .map((e) => TrackPoint.fromMap(readMap(e)))
              .toList(growable: false)
          : const <TrackPoint>[],
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'type': type.name,
        'durationMinutes': durationMinutes,
        'occurredAt': occurredAt,
        'distanceKm': distanceKm,
        'notes': notes?.trim(),
        'dayKey': dayKeyOf(occurredAt),
        // A route is capped before write (see ExerciseRepository) so a long
        // walk cannot push the document past Firestore's 1 MiB limit.
        if (route.isNotEmpty)
          'route': route.map((p) => p.toMap()).toList(growable: false),
      });

  ExerciseRecord copyWith({
    ExerciseType? type,
    int? durationMinutes,
    DateTime? occurredAt,
    double? distanceKm,
    String? notes,
  }) {
    return ExerciseRecord(
      id: id,
      type: type ?? this.type,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      occurredAt: occurredAt ?? this.occurredAt,
      distanceKm: distanceKm ?? this.distanceKm,
      notes: notes ?? this.notes,
      route: route,
    );
  }
}

/// Great-circle distance in kilometres between two coordinates.
///
/// Used to turn a GPS track into a distance without pulling in a geo library.
double haversineKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const double earthRadiusKm = 6371.0088;
  double toRad(double deg) => deg * math.pi / 180.0;

  final double dLat = toRad(lat2 - lat1);
  final double dLon = toRad(lon2 - lon1);

  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Total distance along an ordered GPS track.
double routeDistanceKm(List<TrackPoint> points) {
  if (points.length < 2) return 0;
  double total = 0;
  for (int i = 1; i < points.length; i++) {
    total += haversineKm(
      points[i - 1].latitude,
      points[i - 1].longitude,
      points[i].latitude,
      points[i].longitude,
    );
  }
  return total;
}
