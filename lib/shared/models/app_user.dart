import '../../core/utils/field_mapper.dart';

/// The signed-in user's profile document at `users/{uid}`.
///
/// Deliberately minimal: PetMate stores only what it needs to render the
/// profile screen. Nothing here is ever included in an AI prompt.
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.activePetId,
    required this.createdAt,
    this.lastSeenAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  /// Remembered pet selection so the app reopens on the pet the user was last
  /// working with, across devices.
  final String? activePetId;

  final DateTime createdAt;
  final DateTime? lastSeenAt;

  String get initials {
    final List<String> parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName {
    final String trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      displayName: readString(map['displayName'], fallback: 'Pet Owner'),
      email: readString(map['email']),
      photoUrl: readStringOrNull(map['photoUrl']),
      activePetId: readStringOrNull(map['activePetId']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
      lastSeenAt: readDateOrNull(map['lastSeenAt']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'displayName': displayName.trim(),
        'email': email.trim(),
        'photoUrl': photoUrl,
        'activePetId': activePetId,
        'createdAt': createdAt,
        'lastSeenAt': lastSeenAt,
      });

  AppUser copyWith({
    String? displayName,
    String? photoUrl,
    String? activePetId,
    DateTime? lastSeenAt,
    bool clearActivePet = false,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      activePetId: clearActivePet ? null : (activePetId ?? this.activePetId),
      createdAt: createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
