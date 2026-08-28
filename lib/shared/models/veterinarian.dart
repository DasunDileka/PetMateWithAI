import '../../core/utils/field_mapper.dart';

/// A saved veterinarian contact.
///
/// Stored at `users/{uid}/veterinarians/{id}` — at *user* level rather than
/// under a pet, because one clinic normally treats every pet in a household.
/// Pets link to a vet by id, so a phone-number change is a single write instead
/// of one per pet.
class Veterinarian {
  const Veterinarian({
    required this.id,
    required this.doctorName,
    this.clinicName,
    this.specialisation,
    this.phone,
    this.email,
    this.address,
    this.latitude,
    this.longitude,
    this.notes,
    this.petIds = const <String>[],
    required this.createdAt,
  });

  final String id;
  final String doctorName;
  final String? clinicName;
  final String? specialisation;
  final String? phone;
  final String? email;
  final String? address;

  /// Optional clinic coordinates so saved vets can be plotted on the map
  /// alongside nearby search results.
  final double? latitude;
  final double? longitude;

  final String? notes;

  /// Pets this vet is associated with. Empty means "available to all pets".
  final List<String> petIds;

  final DateTime createdAt;

  bool get hasLocation => latitude != null && longitude != null;

  bool servesPet(String petId) => petIds.isEmpty || petIds.contains(petId);

  String get displayName {
    final String clinic = (clinicName ?? '').trim();
    return clinic.isEmpty ? doctorName : '$doctorName · $clinic';
  }

  /// Initials for the avatar placeholder, e.g. "Dr Anita Perera" -> "AP".
  String get initials {
    final List<String> parts = doctorName
        .replaceAll(RegExp(r'^(Dr\.?|Doctor)\s+', caseSensitive: false), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory Veterinarian.fromMap(String id, Map<String, dynamic> map) {
    return Veterinarian(
      id: id,
      doctorName: readString(map['doctorName'], fallback: 'Veterinarian'),
      clinicName: readStringOrNull(map['clinicName']),
      specialisation: readStringOrNull(map['specialisation']),
      phone: readStringOrNull(map['phone']),
      email: readStringOrNull(map['email']),
      address: readStringOrNull(map['address']),
      latitude: readDoubleOrNull(map['latitude']),
      longitude: readDoubleOrNull(map['longitude']),
      notes: readStringOrNull(map['notes']),
      petIds: readStringList(map['petIds']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'doctorName': doctorName.trim(),
        'clinicName': clinicName?.trim(),
        'specialisation': specialisation?.trim(),
        'phone': phone?.trim(),
        'email': email?.trim(),
        'address': address?.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes?.trim(),
        'petIds': petIds,
        'createdAt': createdAt,
      });

  Veterinarian copyWith({
    String? doctorName,
    String? clinicName,
    String? specialisation,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    String? notes,
    List<String>? petIds,
  }) {
    return Veterinarian(
      id: id,
      doctorName: doctorName ?? this.doctorName,
      clinicName: clinicName ?? this.clinicName,
      specialisation: specialisation ?? this.specialisation,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      notes: notes ?? this.notes,
      petIds: petIds ?? this.petIds,
      createdAt: createdAt,
    );
  }
}
