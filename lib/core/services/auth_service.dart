import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../shared/models/app_user.dart';

/// Thrown by [AuthService] with a message that is always safe to show a user.
///
/// Firebase's own exception strings leak implementation detail ("There is no
/// user record corresponding to this identifier...") and sometimes reveal
/// whether an account exists. Every failure is mapped to neutral copy here.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Wraps Firebase Authentication and the matching `users/{uid}` profile
/// document, so the rest of the app never touches `FirebaseAuth` directly.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  /// Emits on sign-in, sign-out and token refresh. The app's root widget
  /// listens to this, which is what makes the session persist across restarts
  /// without any manual token handling.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Live profile document for the signed-in user.
  Stream<AppUser?> watchProfile() {
    final String? id = uid;
    if (id == null) return Stream<AppUser?>.value(null);
    return _userDoc(id).snapshots().map((snap) {
      final Map<String, dynamic>? data = snap.data();
      if (data == null) return null;
      return AppUser.fromMap(snap.id, data);
    });
  }

  Future<AppUser?> loadProfile() async {
    final String? id = uid;
    if (id == null) return null;
    final DocumentSnapshot<Map<String, dynamic>> snap = await _userDoc(id).get();
    final Map<String, dynamic>? data = snap.data();
    return data == null ? null : AppUser.fromMap(snap.id, data);
  }

  // ------------------------------------------------------------ registration

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final String cleanName = name.trim();
    final String cleanEmail = email.trim().toLowerCase();

    try {
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final User user = cred.user!;
      await user.updateDisplayName(cleanName);

      final AppUser profile = AppUser(
        uid: user.uid,
        displayName: cleanName,
        // Taken from the credential rather than the form field: the security
        // rules compare this against the auth token's email.
        email: user.email ?? cleanEmail,
        createdAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      );

      await _userDoc(user.uid).set(profile.toMap());
      return profile;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    } on FirebaseException catch (e) {
      throw _mapFirestoreError(e);
    }
  }

  // ------------------------------------------------------------------ login

  Future<AppUser?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final String id = cred.user!.uid;

      // A profile can be missing if registration was interrupted after the
      // auth account was created. Repair it rather than failing the sign-in.
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userDoc(id).get();
      if (!snap.exists) {
        final AppUser repaired = AppUser(
          uid: id,
          displayName: cred.user!.displayName ?? 'Pet Owner',
          email: cred.user!.email ?? email.trim().toLowerCase(),
          createdAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
        );
        await _userDoc(id).set(repaired.toMap());
        return repaired;
      }

      await _userDoc(id).update(<String, dynamic>{'lastSeenAt': DateTime.now()});
      return AppUser.fromMap(id, snap.data()!);
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    } on FirebaseException catch (e) {
      throw _mapFirestoreError(e);
    }
  }

  // -------------------------------------------------------------- password

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      // Deliberately does not distinguish "no such account": revealing which
      // addresses are registered would be an account-enumeration weakness.
      if (e.code == 'user-not-found') return;
      throw _mapAuthError(e);
    }
  }

  // --------------------------------------------------------------- profile

  Future<void> updateDisplayName(String name) async {
    final String? id = uid;
    if (id == null) throw const AuthFailure('You are not signed in.');
    final String clean = name.trim();
    if (clean.isEmpty) {
      throw const AuthFailure('Please enter a name.');
    }
    try {
      await _auth.currentUser?.updateDisplayName(clean);
      await _userDoc(id).update(<String, dynamic>{'displayName': clean});
    } on FirebaseException catch (e) {
      throw _mapFirestoreError(e);
    }
  }

  /// Remembers which pet the user was last working with.
  Future<void> setActivePet(String? petId) async {
    final String? id = uid;
    if (id == null) return;
    try {
      await _userDoc(id).set(
        <String, dynamic>{'activePetId': petId},
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      // Non-critical: the selection still applies for this session.
      if (kDebugMode) debugPrint('setActivePet failed: ${e.code}');
    }
  }

  // ---------------------------------------------------------------- logout

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseException catch (e) {
      throw AuthFailure('Could not sign out. Please try again.', code: e.code);
    }
  }

  // -------------------------------------------------------- error mapping

  AuthFailure _mapAuthError(FirebaseAuthException e) {
    final String message = switch (e.code) {
      'invalid-email' => 'That email address is not valid.',
      'user-disabled' => 'This account has been disabled.',
      // Firebase collapses wrong-password and unknown-user into
      // invalid-credential; keeping one message for all three is also the
      // correct behaviour for account enumeration.
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Incorrect email or password.',
      'email-already-in-use' =>
        'An account already exists for that email address.',
      'weak-password' => 'Please choose a stronger password (at least 6 characters).',
      'operation-not-allowed' =>
        'Email sign-in is not enabled for this project.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' =>
        'No internet connection. Please check your network and try again.',
      'requires-recent-login' =>
        'Please sign in again to complete this change.',
      _ => 'Sign-in failed. Please try again.',
    };
    return AuthFailure(message, code: e.code);
  }

  AuthFailure _mapFirestoreError(FirebaseException e) {
    final String message = switch (e.code) {
      'permission-denied' =>
        'You do not have permission to do that.',
      'unavailable' =>
        'Cannot reach the server. Please check your connection.',
      'deadline-exceeded' => 'The request timed out. Please try again.',
      _ => 'Something went wrong. Please try again.',
    };
    return AuthFailure(message, code: e.code);
  }
}
