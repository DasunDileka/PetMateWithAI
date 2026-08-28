import '../../core/utils/field_mapper.dart';
import 'care_enums.dart';

/// A pet belonging to the signed-in user.
///
/// Stored at `users/{uid}/pets/{petId}`. Age is derived from
/// [dateOfBirth] rather than stored, so it can never drift out of date.
class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.species,
    this.breed,
    this.gender = PetGender.unknown,
    this.dateOfBirth,
    this.weightKg = 0,
    this.photoUrl,
    this.notes,
    this.primaryVetId,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final PetSpecies species;
  final String? breed;
  final PetGender gender;
  final DateTime? dateOfBirth;
  final double weightKg;
  final String? photoUrl;
  final String? notes;

  /// Optional link to a saved veterinarian, used to pre-fill appointments.
  final String? primaryVetId;

  final DateTime createdAt;
  final DateTime? updatedAt;

  // ------------------------------------------------------------ derived age

  /// Whole months lived, or null when no date of birth is recorded.
  int? get ageInMonths {
    final DateTime? dob = dateOfBirth;
    if (dob == null) return null;
    final DateTime now = DateTime.now();
    if (dob.isAfter(now)) return 0;
    int months = (now.year - dob.year) * 12 + (now.month - dob.month);
    if (now.day < dob.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  int? get ageInYears {
    final int? months = ageInMonths;
    return months == null ? null : months ~/ 12;
  }

  /// Human-readable age, e.g. "3 years", "1 year 4 months", "7 months".
  /// Falls back to "Age unknown" so the UI never renders an empty slot.
  String get ageLabel {
    final int? months = ageInMonths;
    if (months == null) return 'Age unknown';
    if (months < 1) return 'Under 1 month';
    if (months < 24) {
      final int years = months ~/ 12;
      final int rem = months % 12;
      if (years == 0) return '$months month${months == 1 ? '' : 's'}';
      if (rem == 0) return '1 year';
      return '1 year $rem month${rem == 1 ? '' : 's'}';
    }
    final int years = months ~/ 12;
    return '$years years';
  }

  /// Coarse life stage. Used to phrase AI context ("adult dog") and to vary
  /// recommendations by age — never as a medical classification.
  String get lifeStage {
    final int? months = ageInMonths;
    if (months == null) return 'unknown age';
    return switch (species) {
      PetSpecies.dog when months < 12 => 'puppy',
      PetSpecies.dog when months < 84 => 'adult dog',
      PetSpecies.dog => 'senior dog',
      PetSpecies.cat when months < 12 => 'kitten',
      PetSpecies.cat when months < 120 => 'adult cat',
      PetSpecies.cat => 'senior cat',
      _ when months < 12 => 'young',
      _ => 'adult',
    };
  }

  /// One-line descriptor used in headers: "Labrador • 3 years • 18 kg".
  String get subtitle {
    final List<String> parts = <String>[
      if ((breed ?? '').trim().isNotEmpty) breed!.trim() else species.label,
      ageLabel,
      if (weightKg > 0) '${_trimZeros(weightKg)} kg',
    ];
    return parts.join(' • ');
  }

  static String _trimZeros(double v) {
    final String s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  // ----------------------------------------------------------- persistence

  factory Pet.fromMap(String id, Map<String, dynamic> map) {
    return Pet(
      id: id,
      name: readString(map['name'], fallback: 'Unnamed'),
      species: readEnum(
        map['species'],
        PetSpecies.values,
        PetSpecies.other,
        (e) => e.name,
      ),
      breed: readStringOrNull(map['breed']),
      gender: readEnum(
        map['gender'],
        PetGender.values,
        PetGender.unknown,
        (e) => e.name,
      ),
      dateOfBirth: readDateOrNull(map['dateOfBirth']),
      weightKg: readDouble(map['weightKg']),
      photoUrl: readStringOrNull(map['photoUrl']),
      notes: readStringOrNull(map['notes']),
      primaryVetId: readStringOrNull(map['primaryVetId']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
      updatedAt: readDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'name': name.trim(),
        'species': species.name,
        'breed': breed?.trim(),
        'gender': gender.name,
        'dateOfBirth': dateOfBirth,
        'weightKg': weightKg,
        'photoUrl': photoUrl,
        'notes': notes?.trim(),
        'primaryVetId': primaryVetId,
        'createdAt': createdAt,
        'updatedAt': updatedAt ?? DateTime.now(),
      });

  Pet copyWith({
    String? id,
    String? name,
    PetSpecies? species,
    String? breed,
    PetGender? gender,
    DateTime? dateOfBirth,
    double? weightKg,
    String? photoUrl,
    String? notes,
    String? primaryVetId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearPhoto = false,
  }) {
    return Pet(
      id: id ?? this.id,
      name: name ?? this.name,
      species: species ?? this.species,
      breed: breed ?? this.breed,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      weightKg: weightKg ?? this.weightKg,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      notes: notes ?? this.notes,
      primaryVetId: primaryVetId ?? this.primaryVetId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) => other is Pet && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
