import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';
import '../theme/app_colors.dart';
import 'firestore_refs.dart';

/// User-controllable reminder categories.
class NotificationPreferences {
  const NotificationPreferences({
    this.feeding = true,
    this.medicine = true,
    this.vaccination = true,
    this.grooming = true,
    this.appointments = true,
    this.insights = true,
  });

  final bool feeding;
  final bool medicine;
  final bool vaccination;
  final bool grooming;
  final bool appointments;

  /// AI-detected pattern alerts.
  final bool insights;

  bool enabledFor(CareType type) => switch (type) {
        CareType.feeding => feeding,
        CareType.medicine => medicine,
        CareType.vaccination => vaccination,
        CareType.grooming => grooming,
        CareType.appointment => appointments,
        CareType.exercise => insights,
      };

  Map<String, dynamic> toMap() => <String, dynamic>{
        'feeding': feeding,
        'medicine': medicine,
        'vaccination': vaccination,
        'grooming': grooming,
        'appointments': appointments,
        'insights': insights,
      };

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) =>
      NotificationPreferences(
        feeding: map['feeding'] as bool? ?? true,
        medicine: map['medicine'] as bool? ?? true,
        vaccination: map['vaccination'] as bool? ?? true,
        grooming: map['grooming'] as bool? ?? true,
        appointments: map['appointments'] as bool? ?? true,
        insights: map['insights'] as bool? ?? true,
      );

  NotificationPreferences copyWith({
    bool? feeding,
    bool? medicine,
    bool? vaccination,
    bool? grooming,
    bool? appointments,
    bool? insights,
  }) =>
      NotificationPreferences(
        feeding: feeding ?? this.feeding,
        medicine: medicine ?? this.medicine,
        vaccination: vaccination ?? this.vaccination,
        grooming: grooming ?? this.grooming,
        appointments: appointments ?? this.appointments,
        insights: insights ?? this.insights,
      );
}

/// Schedules and cancels PetMate's local reminders.
///
/// Local notifications rather than push: every reminder PetMate sends is
/// derived from data already on the device, so a server round-trip would add
/// cost and a privacy surface for no benefit. It also means reminders keep
/// working with no network — and it is fully demonstrable on an emulator.
///
/// Notification ids are derived deterministically from the owning record's id,
/// so rescheduling replaces a reminder instead of stacking duplicates.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _permissionGranted = false;

  bool get permissionGranted => _permissionGranted;

  // ----------------------------------------------------------- preferences

  NotificationPreferences _prefs = const NotificationPreferences();

  /// The reminder categories the owner has switched on.
  ///
  /// Held here rather than on the settings screen so that every `schedule*`
  /// call honours the choice. Previously the switches only moved local UI
  /// state: they were forgotten when the screen closed and nothing ever read
  /// them, so turning a category off had no effect on what was scheduled.
  NotificationPreferences get preferences => _prefs;

  Future<NotificationPreferences> loadPreferences(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await Refs.settings(uid, 'notifications').get();
      final Map<String, dynamic>? data = snap.data();
      if (data != null) _prefs = NotificationPreferences.fromMap(data);
    } catch (e) {
      if (kDebugMode) debugPrint('preference load failed: $e');
    }
    return _prefs;
  }

  /// Persists the choice and drops the reminders the owner just turned off —
  /// without this a category could stop scheduling new reminders while the
  /// ones already queued kept firing.
  Future<void> savePreferences(String uid, NotificationPreferences prefs) async {
    final NotificationPreferences previous = _prefs;
    _prefs = prefs;

    for (final CareType type in CareType.values) {
      if (previous.enabledFor(type) && !prefs.enabledFor(type)) {
        await cancelCategory(type);
      }
    }

    try {
      await Refs.settings(uid, 'notifications').set(prefs.toMap());
    } catch (e) {
      if (kDebugMode) debugPrint('preference save failed: $e');
    }
  }

  // Separate channels let the user silence one category in Android settings
  // without losing the rest.
  static const AndroidNotificationChannel _careChannel =
      AndroidNotificationChannel(
    'petmate_care',
    'Care reminders',
    description: 'Feeding, medication and grooming reminders.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _medicalChannel =
      AndroidNotificationChannel(
    'petmate_medical',
    'Vaccinations and appointments',
    description: 'Vaccination due dates and veterinary appointments.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _insightChannel =
      AndroidNotificationChannel(
    'petmate_insights',
    'Care insights',
    description: 'Patterns PetMate notices in your pet\'s recorded care.',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // The device's own zone is not exposed by the timezone package; the plugin
    // resolves scheduling against the local zone we set here. UTC offset is
    // applied per-schedule via tz.local.
    tz.setLocalLocation(tz.getLocation(await _resolveTimeZone()));

    const AndroidInitializationSettings android =
        // Monochrome silhouette, not the launcher icon: Android flattens the
        // small icon to a single tint, so a full-colour asset renders as a
        // featureless square.
        AndroidInitializationSettings('@drawable/ic_notification');

    const InitializationSettings settings =
        InitializationSettings(android: android);

    await _plugin.initialize(settings: settings);

    final AndroidFlutterLocalNotificationsPlugin? impl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (impl != null) {
      await impl.createNotificationChannel(_careChannel);
      await impl.createNotificationChannel(_medicalChannel);
      await impl.createNotificationChannel(_insightChannel);
    }

    _ready = true;
  }

  /// Reads the *current* OS permission state rather than the cached one.
  ///
  /// [permissionGranted] is only populated after [requestPermission] runs, so
  /// on a fresh launch it is false even for a user who granted permission long
  /// ago — which made the settings screen claim permission was missing every
  /// time the app restarted. Settings therefore asks the platform directly.
  Future<bool> refreshPermissionStatus() async {
    await init();
    try {
      final AndroidFlutterLocalNotificationsPlugin? impl =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      _permissionGranted = await impl?.areNotificationsEnabled() ?? false;
      return _permissionGranted;
    } catch (e) {
      if (kDebugMode) debugPrint('notification permission check failed: $e');
      return _permissionGranted;
    }
  }

  /// Requests the Android 13+ runtime notification permission.
  /// Returns false rather than throwing when the user declines, so the caller
  /// can degrade gracefully instead of breaking.
  Future<bool> requestPermission() async {
    await init();
    try {
      final AndroidFlutterLocalNotificationsPlugin? impl =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      _permissionGranted = await impl?.requestNotificationsPermission() ?? false;
      return _permissionGranted;
    } catch (e) {
      if (kDebugMode) debugPrint('notification permission failed: $e');
      _permissionGranted = false;
      return false;
    }
  }

  Future<String> _resolveTimeZone() async {
    try {
      // DateTime.now().timeZoneName gives an abbreviation that the tz database
      // cannot always resolve, so fall back to a fixed zone on failure.
      final Duration offset = DateTime.now().timeZoneOffset;
      for (final String name in tz.timeZoneDatabase.locations.keys) {
        final tz.Location loc = tz.getLocation(name);
        if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return name;
      }
    } catch (_) {
      // fall through
    }
    return 'UTC';
  }

  // ------------------------------------------------------------ scheduling

  // ------------------------------------------------------------- id blocks

  /// Ids are partitioned into one contiguous block per reminder category.
  ///
  /// A plain hash of the record key gives a stable id, but nothing about that
  /// id says which category it belongs to — so when the owner switched a
  /// category off there was no way to find the reminders already scheduled for
  /// it. Reserving a block per category makes the category recoverable from the
  /// id alone, which is what [cancelCategory] needs.
  static const int _blockSize = 100000000;

  static int _blockStart(CareType type) => switch (type) {
        CareType.feeding => 0,
        CareType.medicine => _blockSize,
        CareType.vaccination => _blockSize * 2,
        CareType.grooming => _blockSize * 3,
        CareType.appointment => _blockSize * 4,
        CareType.exercise => _blockSize * 5,
      };

  /// Block reserved for one-off notifications that belong to no category.
  static const int _utilityBlockStart = _blockSize * 6;

  /// Stable id for [key] inside [type]'s block.
  static int _idFor(CareType type, String key) =>
      _blockStart(type) + (key.hashCode.abs() % _blockSize);

  /// The category an id belongs to, or null for the utility block.
  static CareType? _categoryForId(int id) {
    for (final CareType type in CareType.values) {
      final int start = _blockStart(type);
      if (id >= start && id < start + _blockSize) return type;
    }
    return null;
  }

  /// Cancels every pending reminder in one category.
  Future<void> cancelCategory(CareType type) async {
    await init();
    try {
      final int start = _blockStart(type);
      final int end = start + _blockSize;
      for (final PendingNotificationRequest r
          in await _plugin.pendingNotificationRequests()) {
        if (r.id >= start && r.id < end) await _plugin.cancel(id: r.id);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('cancelCategory failed: $e');
    }
  }

  NotificationDetails _details(AndroidNotificationChannel channel) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        color: AppColors.navy,
        styleInformation: const BigTextStyleInformation(''),
      ),
    );
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required AndroidNotificationChannel channel,
    DateTimeComponents? repeats,
  }) async {
    await init();

    // The id carries its own category (see the id-block note above), so this
    // one check covers every reminder type — there is no scheduling path that
    // can bypass the owner's choice.
    final CareType? category = _categoryForId(id);
    if (category != null && !_prefs.enabledFor(category)) return;

    // Never schedule in the past — the plugin would fire it immediately, which
    // reads as a bug to the user.
    if (repeats == null && when.isBefore(DateTime.now())) return;

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details(channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeats,
      );
    } catch (e) {
      // Exact-alarm permission can be refused on Android 12+; a missing
      // reminder must not crash the app.
      if (kDebugMode) debugPrint('schedule failed ($title): $e');
    }
  }

  // --------------------------------------------------------------- feeding

  Future<void> scheduleFeeding({
    required Pet pet,
    required FeedingSchedule schedule,
  }) async {
    final DateTime now = DateTime.now();
    DateTime next = schedule.dueOn(now);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));

    await _schedule(
      id: _idFor(CareType.feeding, 'feeding_${pet.id}_${schedule.id}'),
      title: '${CareType.feeding.emoji} Time for ${pet.name}\'s ${schedule.label.toLowerCase()}',
      body: schedule.quantity == null
          ? 'Tap to mark it as done.'
          : '${schedule.portionLabel}. Tap to mark it as done.',
      when: next,
      channel: _careChannel,
      repeats: DateTimeComponents.time,
    );
  }

  Future<void> cancelFeeding(String petId, String scheduleId) =>
      _cancel(_idFor(CareType.feeding, 'feeding_${petId}_$scheduleId'));

  // -------------------------------------------------------------- medicine

  Future<void> scheduleMedicine({
    required Pet pet,
    required Medicine medicine,
  }) async {
    if (!medicine.isActive) return;

    final DateTime now = DateTime.now();
    final List<DateTime> todayTimes = medicine.dueTimesOn(now);

    for (int i = 0; i < todayTimes.length; i++) {
      DateTime when = todayTimes[i];
      if (when.isBefore(now)) when = when.add(const Duration(days: 1));

      await _schedule(
        id: _idFor(CareType.medicine, 'medicine_${pet.id}_${medicine.id}_$i'),
        title: '${CareType.medicine.emoji} ${pet.name}\'s medicine is due',
        body: '${medicine.name} — ${medicine.dosage}',
        when: when,
        channel: _careChannel,
        repeats: medicine.frequency == MedicineFrequency.onceDaily ||
                medicine.frequency == MedicineFrequency.twiceDaily ||
                medicine.frequency == MedicineFrequency.threeTimesDaily
            ? DateTimeComponents.time
            : null,
      );
    }
  }

  Future<void> cancelMedicine(String petId, String medicineId) async {
    for (int i = 0; i < 3; i++) {
      await _cancel(_idFor(CareType.medicine, 'medicine_${petId}_${medicineId}_$i'));
    }
  }

  // ----------------------------------------------------------- vaccination

  /// Reminds five days ahead, at 9am, matching the brief's example.
  Future<void> scheduleVaccination({
    required Pet pet,
    required Vaccination vaccination,
  }) async {
    final DateTime? due = vaccination.nextDueAt;
    if (due == null) return;

    final DateTime remindAt =
        DateTime(due.year, due.month, due.day, 9).subtract(const Duration(days: 5));

    await _schedule(
      id: _idFor(CareType.vaccination, 'vaccination_${pet.id}_${vaccination.id}'),
      title: '${CareType.vaccination.emoji} ${pet.name}\'s vaccination is due soon',
      body: '${vaccination.vaccineName} is due on '
          '${due.day}/${due.month}/${due.year}.',
      when: remindAt,
      channel: _medicalChannel,
    );
  }

  Future<void> cancelVaccination(String petId, String id) =>
      _cancel(_idFor(CareType.vaccination, 'vaccination_${petId}_$id'));

  // -------------------------------------------------------------- grooming

  Future<void> scheduleGrooming({
    required Pet pet,
    required GroomingRecord grooming,
  }) async {
    final DateTime? due = grooming.nextDueAt;
    if (due == null) return;

    final DateTime remindAt =
        DateTime(due.year, due.month, due.day, 9).subtract(const Duration(days: 1));

    await _schedule(
      id: _idFor(CareType.grooming, 'grooming_${pet.id}_${grooming.id}'),
      title: '${CareType.grooming.emoji} ${pet.name}\'s grooming is due tomorrow',
      body: '${grooming.type.label} is scheduled for tomorrow.',
      when: remindAt,
      channel: _careChannel,
    );
  }

  Future<void> cancelGrooming(String petId, String id) =>
      _cancel(_idFor(CareType.grooming, 'grooming_${petId}_$id'));

  // ----------------------------------------------------------- appointment

  Future<void> scheduleAppointment({
    required Pet pet,
    required Appointment appointment,
  }) async {
    if (appointment.status != AppointmentStatus.upcoming) return;

    final DateTime remindAt =
        appointment.scheduledAt.subtract(const Duration(days: 1));

    await _schedule(
      id: _idFor(CareType.appointment, 'appointment_${pet.id}_${appointment.id}'),
      title: '${CareType.appointment.emoji} ${pet.name} has a vet appointment tomorrow',
      body: '${appointment.reason} — ${appointment.whenLabel}'
          '${appointment.veterinarianName == null ? '' : ' with ${appointment.veterinarianName}'}.',
      when: remindAt,
      channel: _medicalChannel,
    );
  }

  Future<void> cancelAppointment(String petId, String id) =>
      _cancel(_idFor(CareType.appointment, 'appointment_${petId}_$id'));

  // --------------------------------------------------------------- insight

  /// One-off alert for a detected pattern.
  ///
  /// Deliberately rate-limited by the caller to at most one per pet per day:
  /// the brief calls for smart notifications, and a pattern alert that fires
  /// repeatedly is just spam.
  Future<void> showInsightAlert({
    required Pet pet,
    required String title,
    required String body,
  }) async {
    await init();
    try {
      await _plugin.show(
        id: _idFor(CareType.exercise, 'insight_${pet.id}'),
        title: title,
        body: body,
        notificationDetails: _details(_insightChannel),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('insight notification failed: $e');
    }
  }

  /// Immediate notification used by the settings screen to prove delivery
  /// works during a demonstration.
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      id: _utilityBlockStart,
      title: '🐾 PetMate notifications are working',
      body: 'This is how your care reminders will appear.',
      notificationDetails: _details(_careChannel),
    );
  }

  // ------------------------------------------------------------------ misc

  Future<void> _cancel(int id) async {
    await init();
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      if (kDebugMode) debugPrint('cancel failed: $e');
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }
}
