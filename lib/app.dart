import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/care/care_controller.dart';
import 'features/pets/pet_controller.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/splash_screen.dart';
import 'shared/models/pet.dart';
import 'shared/widgets/brand.dart';
import 'shared/widgets/state_views.dart';

/// Root widget.
///
/// **Provider placement matters here.** Every screen in PetMate is pushed onto
/// the root `Navigator` with a `MaterialPageRoute`, and that Navigator lives
/// *inside* `MaterialApp` — above whatever `home:` builds. A provider created
/// inside `home:` is therefore invisible to any pushed route, which surfaces at
/// runtime as a missing-provider error on the pushed screen.
///
/// The fix is to inject the scoped controllers through [MaterialApp.builder],
/// which wraps the Navigator itself. Everything below — including every pushed
/// route — can then resolve them.
///
/// Scoping still mirrors data lifetime:
///  * [AuthController] — whole app; owns the session.
///  * [PetController]  — only while signed in, keyed by uid so a different
///    account gets a fresh controller and fresh Firestore listeners.
///  * [CareController] — only while a pet is selected.
class PetMateApp extends StatelessWidget {
  const PetMateApp({super.key, this.startupError});

  final String? startupError;

  /// Needed so sign-out can unwind the navigation stack from outside any
  /// screen's context — see [_SignedInScopeState].
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>(
      create: (_) => AuthController(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        builder: (BuildContext context, Widget? child) {
          // Clamp text scaling: PetMate honours the user's larger-text setting
          // for accessibility, but past 1.4x the dashboard cards overflow.
          final MediaQueryData data = MediaQuery.of(context);
          return MediaQuery(
            data: data.copyWith(
              textScaler: data.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.4,
              ),
            ),
            child: _SignedInScope(child: child ?? const SizedBox.shrink()),
          );
        },
        home: startupError != null
            ? _StartupErrorScreen(message: startupError!)
            : const AuthGate(),
      ),
    );
  }
}

/// Provides [PetController] (and beneath it [CareController]) above the
/// Navigator whenever a user is signed in.
///
/// **Sign-out needs care.** Swapping what `home:` builds does *not* pop routes
/// that were pushed on top of it, so at the moment the session ends there may
/// still be a Profile, Care or Vet screen mounted — and every one of those
/// watches [AuthController], so they all rebuild in the very frame the session
/// ends. Dropping the scoped providers in that same frame leaves those screens
/// looking up a provider that no longer exists, which throws
/// `ProviderNotFoundError`.
///
/// So teardown is ordered explicitly:
///  1. the scope is *retained* for the frame in which sign-out happens;
///  2. after that frame, every pushed route is popped back to the auth gate;
///  3. only then are the controllers released.
///
/// Step 2 matters on its own account: leaving the previous user's screens on
/// the stack would let the back gesture reveal them after logout.
class _SignedInScope extends StatefulWidget {
  const _SignedInScope({required this.child});

  final Widget child;

  @override
  State<_SignedInScope> createState() => _SignedInScopeState();
}

class _SignedInScopeState extends State<_SignedInScope> {
  /// The uid whose controllers are currently provided. Deliberately allowed to
  /// outlive the session by one frame, per the ordering above.
  String? _scopeUid;

  /// Guards against scheduling the unwind more than once while the post-frame
  /// callback is pending.
  bool _tearingDown = false;

  void _scheduleTeardown() {
    if (_tearingDown) return;
    _tearingDown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      PetMateApp.navigatorKey.currentState?.popUntil(
        (Route<dynamic> route) => route.isFirst,
      );
      if (!mounted) return;
      setState(() {
        _scopeUid = null;
        _tearingDown = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final String? uid = auth.uid;
    final bool signedIn =
        auth.status == AuthStatus.authenticated && uid != null;

    if (signedIn) {
      // A different account signing in must not inherit the previous scope.
      if (_scopeUid != null && _scopeUid != uid) _scopeUid = null;
      _scopeUid = uid;
      _tearingDown = false;
    } else if (_scopeUid != null) {
      _scheduleTeardown();
    }

    final String? scopeUid = _scopeUid;
    if (scopeUid == null) return widget.child;

    return ChangeNotifierProvider<PetController>(
      // Keying by uid guarantees a fresh controller — and fresh listeners — if
      // a different account signs in without the app restarting.
      key: ValueKey<String>(scopeUid),
      create: (_) => PetController(uid: scopeUid),
      child: _ActivePetScope(uid: scopeUid, child: widget.child),
    );
  }
}

/// Provides [CareController] for the selected pet.
///
/// Deliberately conditional: with no pet there is nothing to subscribe to, and
/// creating the controller anyway would open nine Firestore listeners against a
/// pet id that does not exist.
class _ActivePetScope extends StatelessWidget {
  const _ActivePetScope({required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final PetController pets = context.watch<PetController>();
    final Pet? active = pets.activePet;

    if (active == null) return child;

    return ChangeNotifierProxyProvider<PetController, CareController>(
      create: (_) => CareController(uid: uid, pet: active),
      update: (_, PetController petController, CareController? care) {
        final Pet? current = petController.activePet;
        if (care != null && current != null) care.switchPet(current);
        return care ?? CareController(uid: uid, pet: active);
      },
      child: child,
    );
  }
}

/// Routes between the splash, the auth flow and the authenticated app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return switch (auth.status) {
      AuthStatus.unknown => const SplashScreen(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.authenticated => const HomeShell(),
    };
  }
}

/// Shown when Firebase could not be reached during startup.
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const PetMateWordmark(markSize: 84),
              const SizedBox(height: AppTheme.gapXxl),
              ErrorView(message: message),
            ],
          ),
        ),
      ),
    );
  }
}
