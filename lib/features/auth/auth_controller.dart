import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/auth_service.dart';
import '../../shared/models/app_user.dart';

enum AuthStatus {
  /// Firebase has not yet reported whether a session exists.
  unknown,
  authenticated,
  unauthenticated,
}

/// Owns the authentication session for the whole app.
///
/// The root widget rebuilds on [status], which is what gives PetMate a
/// persistent session: Firebase restores the token on launch, `authStateChanges`
/// fires, and the user lands back on the dashboard without re-entering
/// credentials.
class AuthController extends ChangeNotifier {
  AuthController({AuthService? service})
      : _service = service ?? AuthService() {
    _listen();
  }

  final AuthService _service;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _profile;
  String? _error;
  bool _busy = false;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  String? get error => _error;
  bool get busy => _busy;

  String? get uid => _service.uid;
  bool get isSignedIn => _status == AuthStatus.authenticated;

  void _listen() {
    _authSub = _service.authStateChanges.listen((User? user) {
      if (user == null) {
        _profileSub?.cancel();
        _profileSub = null;
        _profile = null;
        _status = AuthStatus.unauthenticated;
      } else {
        _status = AuthStatus.authenticated;
        _watchProfile();
      }
      notifyListeners();
    });
  }

  void _watchProfile() {
    _profileSub?.cancel();
    _profileSub = _service.watchProfile().listen(
      (AppUser? user) {
        _profile = user;
        notifyListeners();
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('profile stream error: $e');
      },
    );
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Runs an auth action, funnelling every failure into [error] as user-safe
  /// copy. Returns true on success.
  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await action();
      return true;
    } on AuthFailure catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('auth action failed: $e');
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) =>
      _run(() => _service.register(
            name: name,
            email: email,
            password: password,
          ));

  Future<bool> signIn({required String email, required String password}) =>
      _run(() => _service.signIn(email: email, password: password));

  Future<bool> sendPasswordReset(String email) =>
      _run(() => _service.sendPasswordReset(email));

  Future<bool> updateDisplayName(String name) =>
      _run(() => _service.updateDisplayName(name));

  Future<void> setActivePet(String? petId) => _service.setActivePet(petId);

  Future<void> signOut() async {
    // Cancel listeners before signing out: an in-flight snapshot on a
    // now-unauthenticated user surfaces as a permission-denied error.
    await _profileSub?.cancel();
    _profileSub = null;
    _profile = null;
    await _service.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
