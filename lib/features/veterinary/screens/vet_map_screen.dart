import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/exercise.dart' show haversineKm;
import '../../../shared/models/veterinarian.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../vet_repository.dart';
import 'vet_form_screen.dart';

/// Map of the user's saved veterinary clinics relative to their position.
///
/// Together with the walk tracker this covers the mapping half of LO2. Tiles
/// come from OpenStreetMap, so no billing account or Maps API key is needed and
/// the screen works on a clean emulator. Distances are computed locally with
/// the haversine formula rather than by a routing service.
class VetMapScreen extends StatefulWidget {
  const VetMapScreen({super.key});

  @override
  State<VetMapScreen> createState() => _VetMapScreenState();
}

class _VetMapScreenState extends State<VetMapScreen> {
  final LocationService _location = const LocationService();
  final MapController _map = MapController();

  LatLng? _me;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _me = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      // Anything the plugin throws that is not a LocationFailure would
      // otherwise leave this screen stuck on its spinner with no retry.
      if (kDebugMode) debugPrint('clinic locate failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not get a location fix on this device.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinics near me'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _locate,
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'Recentre on my location',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<Veterinarian>>(
          stream: VetRepository(uid: uid).watchVeterinarians(),
          builder: (context, snapshot) {
            final List<Veterinarian> all =
                snapshot.data ?? const <Veterinarian>[];
            final List<Veterinarian> mapped =
                all.where((Veterinarian v) => v.hasLocation).toList();

            if (_loading) {
              return const LoadingView(message: 'Finding your location…');
            }

            if (_me == null) {
              return ErrorView(
                message: _error ??
                    'Location unavailable. On an emulator, set a position in '
                        'Extended controls ▸ Location.',
                onRetry: _locate,
              );
            }

            // Nearest first so the list answers "where do I go?" directly.
            final List<({Veterinarian vet, double km})> ranked = mapped
                .map((Veterinarian v) => (
                      vet: v,
                      km: haversineKm(
                        _me!.latitude,
                        _me!.longitude,
                        v.latitude!,
                        v.longitude!,
                      ),
                    ))
                .toList()
              ..sort((a, b) => a.km.compareTo(b.km));

            return Column(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: <Widget>[
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _me!,
                          initialZoom: 13,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                        ),
                        children: <Widget>[
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'dasun.petmate.com',
                            maxZoom: 19,
                          ),
                          MarkerLayer(
                            markers: <Marker>[
                              Marker(
                                point: _me!,
                                width: 26,
                                height: 26,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.navy,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                  ),
                                ),
                              ),
                              ...mapped.map((Veterinarian v) => Marker(
                                    point: LatLng(v.latitude!, v.longitude!),
                                    width: 40,
                                    height: 40,
                                    child: Tooltip(
                                      message: v.displayName,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: AppColors.vet,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.local_hospital_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  )),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: const Text(
                            '© OpenStreetMap contributors',
                            style:
                                TextStyle(fontSize: 9, color: Colors.black87),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: mapped.isEmpty
                      ? EmptyState(
                          icon: Icons.place_outlined,
                          accent: AppColors.vet,
                          compact: true,
                          title: 'No clinics on the map',
                          message: all.isEmpty
                              ? 'Save a veterinarian, then add their location to '
                                  'see them here.'
                              : 'Your saved vets have no location yet. Edit one '
                                  'and use "Use current" to plot it.',
                          actionLabel: all.isEmpty ? 'Add veterinarian' : null,
                          onAction: all.isEmpty
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const VetFormScreen(),
                                    ),
                                  )
                              : null,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppTheme.gapLg),
                          itemCount: ranked.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppTheme.gapMd),
                          itemBuilder: (context, i) {
                            final ({Veterinarian vet, double km}) r = ranked[i];
                            return AppCard(
                              accent: AppColors.vet,
                              onTap: () => _map.move(
                                LatLng(r.vet.latitude!, r.vet.longitude!),
                                16,
                              ),
                              child: Row(
                                children: <Widget>[
                                  const CareIconTile(
                                    icon: Icons.local_hospital_rounded,
                                    color: AppColors.vet,
                                    size: 38,
                                  ),
                                  const SizedBox(width: AppTheme.gapMd),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          r.vet.doctorName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (r.vet.clinicName != null)
                                          Text(
                                            r.vet.clinicName!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  AppPill(
                                    label: r.km < 1
                                        ? '${(r.km * 1000).round()} m'
                                        : '${r.km.toStringAsFixed(1)} km',
                                    color: AppColors.leaf,
                                    icon: Icons.straighten_rounded,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
