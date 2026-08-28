import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/models/appointment.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/care_event.dart';
import '../../shared/models/exercise.dart';
import '../../shared/models/feeding.dart';
import '../../shared/models/grooming.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/pet.dart';
import '../../shared/models/vaccination.dart';
import '../ai/pet_context_builder.dart';
import '../analytics/care_analytics.dart';
import '../pets/pet_repository.dart' show DataFailure;
import '../veterinary/vet_repository.dart';
import 'care_repository.dart';

/// Aggregates every care stream for the currently selected pet.
///
/// This is where PetMate's real-time behaviour actually happens. Nine Firestore
/// snapshot listeners feed one controller; when any of them emits, the derived
/// analytics and the AI context are recomputed and every listening widget —
/// dashboard tiles, charts, calendar, AI context — updates together, with no
/// manual refresh and no screen reload.
///
/// Recomputation is debounced because a single user action (marking a feeding
/// done) can trigger two or three listeners in quick succession; without it the
/// statistics would be recalculated several times for one logical change.
class CareController extends ChangeNotifier {
  CareController({required this.uid, required Pet pet})
      : _pet = pet,
        _repo = CareRepository(uid: uid, petId: pet.id),
        _vetRepo = VetRepository(uid: uid) {
    _subscribe();
  }

  final String uid;
  CareRepository _repo;
  final VetRepository _vetRepo;
  Pet _pet;

  Pet get pet => _pet;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  Timer? _debounce;

  // ------------------------------------------------------------- raw data
  List<FeedingSchedule> _schedules = const <FeedingSchedule>[];
  List<FeedingRecord> _todayFeedings = const <FeedingRecord>[];
  List<FeedingRecord> _recentFeedings = const <FeedingRecord>[];
  List<ExerciseRecord> _exercise = const <ExerciseRecord>[];
  List<Medicine> _medicines = const <Medicine>[];
  List<MedicineDose> _doses = const <MedicineDose>[];
  List<Vaccination> _vaccinations = const <Vaccination>[];
  List<GroomingRecord> _grooming = const <GroomingRecord>[];
  List<Appointment> _appointments = const <Appointment>[];

  List<FeedingSchedule> get schedules => _schedules;
  List<FeedingRecord> get todayFeedings => _todayFeedings;
  List<FeedingRecord> get recentFeedings => _recentFeedings;
  List<ExerciseRecord> get exercise => _exercise;
  List<Medicine> get medicines => _medicines;
  List<MedicineDose> get doses => _doses;
  List<Vaccination> get vaccinations => _vaccinations;
  List<GroomingRecord> get grooming => _grooming;
  List<Appointment> get appointments => _appointments;

  CareRepository get repository => _repo;
  VetRepository get vetRepository => _vetRepo;

  // ------------------------------------------------------------- derived
  PetContext? _context;
  int _pendingStreams = 9;
  String? _error;

  /// Fully loaded once every stream has delivered its first snapshot.
  bool get loading => _pendingStreams > 0;
  String? get error => _error;

  PetContext? get context => _context;
  TodaySnapshot? get today => _context?.snapshot;
  TrendResult? get trend => _context?.trend;
  List<CareAnomaly> get anomalies => _context?.anomalies ?? const <CareAnomaly>[];
  CompletionStat? get feedingStat => _context?.feeding;
  CompletionStat? get medicationStat => _context?.medication;

  /// Switches to a different pet without recreating the controller, so the
  /// widget tree above it is not rebuilt from scratch.
  ///
  /// **This is called from a `ChangeNotifierProxyProvider.update` callback,
  /// which runs during build.** It must therefore never notify listeners
  /// synchronously: doing so schedules another build, whose `update` calls
  /// this again, and the tree rebuilds every frame forever. The visible
  /// symptom is subtle and nasty — the screen looks fine and still scrolls,
  /// but every tap is dropped, because each rebuild resets the gesture
  /// recognisers mid-press. All notifications here are therefore deferred
  /// through the debounced [_scheduleRecompute].
  void switchPet(Pet pet) {
    if (pet.id == _pet.id) {
      // Same pet. Only recompute if something the context actually depends on
      // changed — an identical object must not trigger any work at all.
      final bool relevantChange = pet.name != _pet.name ||
          pet.species != _pet.species ||
          pet.breed != _pet.breed ||
          pet.weightKg != _pet.weightKg ||
          pet.dateOfBirth != _pet.dateOfBirth ||
          pet.notes != _pet.notes;

      _pet = pet;
      if (relevantChange) _scheduleRecompute();
      return;
    }

    _pet = pet;
    _repo = CareRepository(uid: uid, petId: pet.id);
    _context = null;
    _pendingStreams = 9;
    _subscribe();
    // Deferred, for the reason described above.
    _scheduleRecompute();
  }

  void _subscribe() {
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    _subs.clear();

    _bind<List<FeedingSchedule>>(
        _repo.watchFeedingSchedules(), (v) => _schedules = v);
    _bind<List<FeedingRecord>>(
        _repo.watchFeedingRecordsForDay(DateTime.now()), (v) => _todayFeedings = v);
    _bind<List<FeedingRecord>>(
        _repo.watchRecentFeedingRecords(), (v) => _recentFeedings = v);
    _bind<List<ExerciseRecord>>(_repo.watchRecentExercise(), (v) => _exercise = v);
    _bind<List<Medicine>>(_repo.watchMedicines(), (v) => _medicines = v);
    _bind<List<MedicineDose>>(_repo.watchRecentDoses(), (v) => _doses = v);
    _bind<List<Vaccination>>(_repo.watchVaccinations(), (v) => _vaccinations = v);
    _bind<List<GroomingRecord>>(_repo.watchGrooming(), (v) => _grooming = v);
    _bind<List<Appointment>>(
        _vetRepo.watchAppointments(_pet.id), (v) => _appointments = v);
  }

  void _bind<T>(Stream<T> stream, void Function(T) assign) {
    bool first = true;
    _subs.add(stream.listen(
      (T value) {
        assign(value);
        if (first) {
          first = false;
          _pendingStreams = (_pendingStreams - 1).clamp(0, 9);
        }
        _scheduleRecompute();
      },
      onError: (Object e) {
        if (first) {
          first = false;
          _pendingStreams = (_pendingStreams - 1).clamp(0, 9);
        }
        _error = e is DataFailure
            ? e.message
            : 'Some care data could not be loaded.';
        if (kDebugMode) debugPrint('care stream error: $e');
        notifyListeners();
      },
    ));
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _recompute);
  }

  void _recompute() {
    _context = PetContextBuilder.build(
      pet: _pet,
      feedingSchedules: _schedules,
      feedingRecords: _mergedFeedingRecords(),
      exercise: _exercise,
      medicines: _medicines,
      doses: _doses,
      vaccinations: _vaccinations,
      grooming: _grooming,
      appointments: _appointments,
    );
    notifyListeners();
  }

  /// Today's records come from a separate day-keyed listener, so they are
  /// merged with the window query and de-duplicated by document id.
  List<FeedingRecord> _mergedFeedingRecords() {
    final Map<String, FeedingRecord> byId = <String, FeedingRecord>{};
    for (final FeedingRecord r in _recentFeedings) {
      byId[r.id] = r;
    }
    for (final FeedingRecord r in _todayFeedings) {
      byId[r.id] = r;
    }
    return byId.values.toList(growable: false);
  }

  // ------------------------------------------------------- today helpers

  /// Status of a schedule for today, defaulting to pending when the owner has
  /// not yet acted on it.
  CareStatus statusForSchedule(FeedingSchedule schedule) {
    for (final FeedingRecord r in _todayFeedings) {
      if (r.scheduleId == schedule.id) return r.status;
    }
    // A slot whose time has passed without being logged reads as missed.
    return schedule.dueOn(DateTime.now()).isBefore(DateTime.now())
        ? CareStatus.missed
        : CareStatus.pending;
  }

  /// Medicine doses due today, paired with whatever has been recorded.
  List<({Medicine medicine, DateTime dueAt, CareStatus status})> dosesDueToday() {
    final DateTime now = DateTime.now();
    final List<({Medicine medicine, DateTime dueAt, CareStatus status})> out =
        <({Medicine medicine, DateTime dueAt, CareStatus status})>[];

    for (final Medicine m in _medicines.where((m) => m.isActive)) {
      for (final DateTime due in m.dueTimesOn(now)) {
        CareStatus status = due.isBefore(now) ? CareStatus.missed : CareStatus.pending;
        for (final MedicineDose d in _doses) {
          if (d.medicineId == m.id &&
              d.dueAt.difference(due).inMinutes.abs() < 1) {
            status = d.status;
            break;
          }
        }
        out.add((medicine: m, dueAt: due, status: status));
      }
    }

    out.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return out;
  }

  // -------------------------------------------------- unified care events

  /// Everything that has happened, newest first — the unified history feed.
  List<CareEvent> historyEvents({Set<CareType>? filter}) {
    final List<CareEvent> events = <CareEvent>[
      ..._mergedFeedingRecords().map(CareEvent.fromFeeding),
      ..._exercise.map(CareEvent.fromExercise),
      ..._doses.map(CareEvent.fromMedicineDose),
      ..._vaccinations.map(CareEvent.fromVaccination),
      ..._grooming
          .where((g) => g.lastCompletedAt != null)
          .map(CareEvent.fromGrooming),
      ..._appointments.map(CareEvent.fromAppointment),
    ];

    final List<CareEvent> filtered = filter == null || filter.isEmpty
        ? events
        : events.where((e) => filter.contains(e.type)).toList();

    filtered.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return filtered;
  }

  /// Past events plus forward-looking due dates — what the calendar renders.
  List<CareEvent> calendarEvents() {
    final List<CareEvent> events = historyEvents();

    for (final Vaccination v in _vaccinations) {
      final CareEvent? due = CareEvent.upcomingVaccination(v);
      if (due != null) events.add(due);
    }
    for (final GroomingRecord g in _grooming) {
      final CareEvent? due = CareEvent.upcomingGrooming(g);
      if (due != null) events.add(due);
    }

    events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events;
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
