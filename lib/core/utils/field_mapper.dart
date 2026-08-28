/// Defensive readers for Firestore document maps.
///
/// Documents can be written by an older build, hand-edited in the console, or
/// arrive partially populated while a server timestamp resolves. Every read
/// therefore goes through these helpers rather than a raw cast, so a single
/// malformed field degrades one value instead of throwing and blanking the
/// whole screen.
///
/// Note the deliberate absence of a `cloud_firestore` import: `Timestamp` is
/// duck-typed through `dynamic` so the model layer stays free of any Firebase
/// dependency and remains unit-testable without a Firebase harness.
library;

DateTime? readDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    // Milliseconds since epoch, as written by older clients.
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) return DateTime.tryParse(value);
  try {
    // Firestore `Timestamp` — resolved dynamically, see the note above.
    final dynamic converted = value.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {
    // Not a Timestamp; fall through to null.
  }
  return null;
}

DateTime readDate(dynamic value, {DateTime? fallback}) =>
    readDateOrNull(value) ?? fallback ?? DateTime.fromMillisecondsSinceEpoch(0);

String readString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

String? readStringOrNull(dynamic value) {
  if (value == null) return null;
  final String s = value is String ? value : value.toString();
  return s.trim().isEmpty ? null : s;
}

double readDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? readDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int readInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String v = value.toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}

List<String> readStringList(dynamic value) {
  if (value is List) {
    return value
        .where((e) => e != null)
        .map((e) => e is String ? e : e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

Map<String, dynamic> readMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}

/// Resolves a stored enum name back to a value, tolerating unknown or legacy
/// names by falling back rather than throwing.
T readEnum<T>(dynamic value, List<T> values, T fallback, String Function(T) nameOf) {
  final String raw = readString(value).trim().toLowerCase();
  if (raw.isEmpty) return fallback;
  for (final T candidate in values) {
    if (nameOf(candidate).toLowerCase() == raw) return candidate;
  }
  return fallback;
}

/// Strips keys whose value is null so Firestore documents stay compact and we
/// never overwrite an existing field with an accidental null.
Map<String, dynamic> pruneNulls(Map<String, dynamic> input) {
  final Map<String, dynamic> out = <String, dynamic>{};
  input.forEach((key, value) {
    if (value != null) out[key] = value;
  });
  return out;
}
