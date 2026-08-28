import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/care_enums.dart';
import '../../../shared/models/exercise.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../care_controller.dart';

/// Live GPS walk tracking.
///
/// Evidences the geolocation and mapping element of LO2: the device location
/// stream is sampled into a route, the route is drawn over OpenStreetMap tiles,
/// and distance is computed with the haversine formula rather than taken from
/// the platform. On the emulator the fixes come from the mocked GPS, so this is
/// fully demonstrable without hardware.
class WalkTrackerScreen extends StatefulWidget {
  const WalkTrackerScreen({super.key, required this.care});

  final CareController care;

  @override
  State<WalkTrackerScreen> createState() => _WalkTrackerScreenState();
}

class _WalkTrackerScreenState extends State<WalkTrackerScreen> {
  final LocationService _location = const LocationService();
  final MapController _map = MapController();

  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;

  final List<TrackPoint> _route = <TrackPoint>[];

  bool _preparing = true;
  bool _tracking = false;
  bool _saving = false;
  String? _error;

  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _distanceKm = 0;
  LatLng? _current;

  ExerciseType _type = ExerciseType.walk;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final Position position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _current = LatLng(position.latitude, position.longitude);
        _preparing = false;
        _error = null;
      });
      // Deferred to the next frame. While `_preparing` was true the map was
      // not in the tree at all, and MapController.move throws if it is called
      // before its FlutterMap has been built — which is exactly what happened
      // on the first fix and on every retry.
      _moveMapWhenReady(_current!, 16);
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = e.message;
      });
    } catch (e) {
      // A plugin or platform failure must not leave the screen spinning
      // forever with no way out.
      if (kDebugMode) debugPrint('location prepare failed: $e');
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = 'Could not get a location fix on this device.';
      });
    }
  }

  /// Moves the map once it is actually mounted, ignoring the failure if the
  /// screen has gone away in the meantime.
  void _moveMapWhenReady(LatLng target, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(target, zoom);
      } catch (e) {
        if (kDebugMode) debugPrint('map move skipped: $e');
      }
    });
  }

  void _start() {
    setState(() {
      _tracking = true;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _distanceKm = 0;
      _route.clear();
      _error = null;
    });

    // A separate one-second ticker drives the clock so the elapsed time keeps
    // moving even when the device is stationary and emits no new fixes.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });

    _positionSub = _location.positionStream().listen(
      (Position p) {
        if (!mounted) return;
        final TrackPoint point = TrackPoint(
          latitude: p.latitude,
          longitude: p.longitude,
          recordedAt: DateTime.now(),
        );
        setState(() {
          _route.add(point);
          _distanceKm = routeDistanceKm(_route);
          _current = LatLng(p.latitude, p.longitude);
        });
        _moveMapWhenReady(_current!, _map.camera.zoom);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = 'Lost the GPS signal. The route may be incomplete.');
      },
    );
  }

  Future<void> _stopAndSave() async {
    _positionSub?.cancel();
    _ticker?.cancel();
    _positionSub = null;
    _ticker = null;

    final int minutes = _elapsed.inSeconds < 30 ? 1 : (_elapsed.inSeconds / 60).round();

    setState(() {
      _tracking = false;
      _saving = true;
    });

    try {
      await widget.care.repository.addExercise(ExerciseRecord(
        id: '',
        type: _type,
        durationMinutes: minutes,
        occurredAt: _startedAt ?? DateTime.now(),
        distanceKm: _distanceKm > 0 ? _distanceKm : null,
        route: _route,
        notes: _route.isEmpty ? null : 'Tracked with GPS',
      ));

      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(
        context,
        'Walk saved — $minutes min'
        '${_distanceKm > 0 ? ', ${_distanceKm.toStringAsFixed(2)} km' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save the walk.', isError: true);
    }
  }

  Future<void> _discard() async {
    if (_route.isNotEmpty || _tracking) {
      final bool ok = await confirmAction(
        context,
        title: 'Discard this walk?',
        message: 'The route recorded so far will not be saved.',
        confirmLabel: 'Discard',
      );
      if (!ok) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_tracking,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Track a walk'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _discard,
            tooltip: 'Discard',
          ),
        ),
        body: SafeArea(
          top: false,
          child: _preparing
              ? const LoadingView(message: 'Getting a location fix…')
              : Column(
                  children: <Widget>[
                    Expanded(child: _buildMap()),
                    _buildPanel(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_current == null) {
      return ErrorView(
        message: _error ??
            'Location is unavailable. On an emulator, set a position in '
                'Extended controls ▸ Location.',
        onRetry: () {
          setState(() => _preparing = true);
          _prepare();
        },
      );
    }

    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _current!,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              // OSM's usage policy requires an identifying user agent.
              userAgentPackageName: 'dasun.petmate.com',
              maxZoom: 19,
            ),
            if (_route.length > 1)
              PolylineLayer<Object>(
                polylines: <Polyline<Object>>[
                  Polyline<Object>(
                    points: _route
                        .map((TrackPoint p) => LatLng(p.latitude, p.longitude))
                        .toList(),
                    strokeWidth: 5,
                    color: AppColors.exercise,
                  ),
                ],
              ),
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: _current!,
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.navy.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        // OpenStreetMap requires visible attribution.
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 9, color: Colors.black87),
            ),
          ),
        ),
        if (_error != null)
          Positioned(
            top: AppTheme.gapMd,
            left: AppTheme.gapMd,
            right: AppTheme.gapMd,
            child: InlineNotice(message: _error!),
          ),
      ],
    );
  }

  Widget _buildPanel() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.gapLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _Metric(
                label: 'Duration',
                value: _formatDuration(_elapsed),
                icon: Icons.timer_outlined,
              ),
              _Metric(
                label: 'Distance',
                value: _distanceKm < 1
                    ? '${(_distanceKm * 1000).round()} m'
                    : '${_distanceKm.toStringAsFixed(2)} km',
                icon: Icons.straighten_rounded,
              ),
              _Metric(
                label: 'Points',
                value: _route.length.toString(),
                icon: Icons.timeline_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapLg),

          if (!_tracking) ...<Widget>[
            Wrap(
              spacing: AppTheme.gapSm,
              alignment: WrapAlignment.center,
              children: <ExerciseType>[
                ExerciseType.walk,
                ExerciseType.run,
                ExerciseType.play,
              ]
                  .map((ExerciseType t) => ChoiceChip(
                        avatar: Icon(t.icon, size: 16),
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppTheme.gapLg),
          ],

          SizedBox(
            width: double.infinity,
            child: _saving
                ? const FilledButton(
                    onPressed: null,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  )
                : _tracking
                    ? FilledButton.icon(
                        onPressed: _stopAndSave,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Finish and save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _current == null ? null : _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('Start ${_type.label.toLowerCase()}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.exercise,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final String m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.inkFaint),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
