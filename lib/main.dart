import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/services/notification_service.dart';

/// Application entry point.
///
/// Firebase is initialised without explicit options: on Android the
/// `google-services` Gradle plugin injects the project configuration at build
/// time from `android/app/google-services.json`. That file is gitignored, so no
/// Firebase identifiers are committed to the repository.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // A failed Firebase init must not present a blank screen: the app starts in a
  // degraded state that explains the problem instead.
  String? startupError;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init failed: $e');
    startupError =
        'PetMate could not connect to its cloud services. Please check your '
        'internet connection and restart the app.';
  }

  // Notification setup is best-effort — a device that refuses notifications
  // should still get a fully working app.
  try {
    await NotificationService.instance.init();
  } catch (e) {
    if (kDebugMode) debugPrint('Notification init failed: $e');
  }

  runApp(PetMateApp(startupError: startupError));
}
