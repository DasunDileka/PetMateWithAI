import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location request could not be satisfied. Kept as an enum so the UI can
/// respond appropriately — a denied-forever permission needs a link to system
/// settings, whereas a disabled GPS service needs a different prompt entirely.
enum LocationDenial {
  serviceDisabled,
  denied,
  deniedForever,
  failed,
}

class LocationFailure implements Exception {
  const LocationFailure(this.reason, this.message);

  final LocationDenial reason;
  final String message;

  @override
  String toString() => message;
}

/// Device location for walk tracking and nearby-vet search.
///
/// On the Android emulator the position comes from the emulator's mocked GPS
/// (Extended controls ▸ Location, or `adb emu geo fix`), which is what makes
/// the geolocation requirement of LO2 demonstrable without any physical
/// hardware.
class LocationService {
  const LocationService();

  /// Android location settings.
  ///
  /// `forceLocationManager` selects the platform's own `LocationManager`
  /// instead of the Google Play Services *fused* provider. Two reasons:
  ///
  ///  * The fused provider insists on Google's "Location Accuracy" device
  ///    setting and puts up a system dialog when it is off — which the app
  ///    cannot dismiss and the user may reasonably decline. The platform
  ///    provider has no such dependency.
  ///  * It reads the emulator's mocked GPS directly, so the feature is
  ///    demonstrable on a clean emulator with no Google account.
  ///
  /// The trade-off is slightly slower first fixes on real hardware, which is
  /// acceptable for walk tracking and clinic search.
  static AndroidSettings _androidSettings({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 0,
    Duration? timeLimit,
  }) =>
      AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        forceLocationManager: true,
        timeLimit: timeLimit,
      );

  /// Ensures the service is on and permission is granted, or throws a
  /// [LocationFailure] describing exactly what is missing.
  Future<void> ensureReady() async {
    final bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationFailure(
        LocationDenial.serviceDisabled,
        'Location services are turned off. Please enable them to use this '
        'feature.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        LocationDenial.denied,
        'PetMate needs location access for walk tracking and finding clinics.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationDenial.deniedForever,
        'Location access is permanently denied. Enable it in Settings to use '
        'this feature.',
      );
    }
  }

  /// A single position fix.
  ///
  /// A cold GPS can take a long time to produce its first fix, so a cached
  /// last-known position is accepted as a fallback rather than failing the
  /// screen outright — for plotting nearby clinics, a slightly stale position
  /// is far more useful than none.
  Future<Position> currentPosition() async {
    await ensureReady();

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _androidSettings(
          timeLimit: const Duration(seconds: 12),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('getCurrentPosition failed: $e');

      try {
        final Position? cached = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: true,
        );
        if (cached != null) return cached;
      } catch (inner) {
        if (kDebugMode) debugPrint('getLastKnownPosition failed: $inner');
      }

      throw const LocationFailure(
        LocationDenial.failed,
        'Could not get a location fix. Make sure GPS has a signal — on an '
        'emulator, set a position in Extended controls ▸ Location.',
      );
    }
  }

  /// Continuous updates during a tracked walk.
  ///
  /// A 5 metre [distanceFilterMeters] is the main battery lever here: without
  /// it the platform emits a fix every second even when the pet is standing
  /// still, which burns power and fills the route with duplicate points.
  Stream<Position> positionStream({int distanceFilterMeters = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: _androidSettings(
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}
