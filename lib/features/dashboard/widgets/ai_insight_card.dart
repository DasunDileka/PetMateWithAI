import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/ai_models.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../ai/ai_service.dart';
import '../../ai/pet_context_builder.dart';
import '../../analytics/care_analytics.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';

/// The dashboard's AI card: a personalised daily brief plus any pattern the
/// analytics layer has flagged.
///
/// Generation is driven by the context *fingerprint*, not by widget lifecycle.
/// Rebuilding the dashboard, switching tabs, or returning from another screen
/// will not spend a model call — a new call happens only when the pet's
/// underlying data has actually changed, or the user explicitly refreshes.
class AiInsightCard extends StatefulWidget {
  const AiInsightCard({super.key});

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  AiService? _service;

  AiInsight? _insight;
  bool _loading = false;
  String? _error;

  /// Fingerprint of the data the current insight was generated from.
  String? _generatedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final String? uid = context.read<AuthController>().uid;
    if (uid != null && _service == null) {
      _service = AiService(uid: uid);
    }

    final CareController care = context.watch<CareController>();
    final PetContext? petContext = care.context;

    if (petContext != null &&
        petContext.fingerprint != _generatedFor &&
        !_loading) {
      // Deferred to after the frame: this runs during build, and calling
      // setState synchronously here would be an error.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _generate(petContext, care.pet.name);
      });
    }
  }

  Future<void> _generate(
    PetContext petContext,
    String petName, {
    bool force = false,
  }) async {
    final AiService? service = _service;
    if (service == null) return;

    if (!service.isConfigured) {
      setState(() {
        _generatedFor = petContext.fingerprint;
        _insight = AiInsight(
          id: 'offline',
          kind: AiInsightKind.dailyBrief,
          text: AiService.offlineDailyBrief(
            petName: petName,
            context: petContext,
          ),
          generatedAt: DateTime.now(),
          provider: AiProvider.local,
        );
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _generatedFor = petContext.fingerprint;
    });

    try {
      final AiInsight result = await service.insight(
        petId: context.read<CareController>().pet.id,
        kind: AiInsightKind.dailyBrief,
        context: petContext,
        petName: petName,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _insight = result;
        _loading = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        // Fall back to the deterministic on-device brief so the card is never
        // simply empty when the network or provider is unavailable.
        _insight ??= AiInsight(
          id: 'offline',
          kind: AiInsightKind.dailyBrief,
          text: AiService.offlineDailyBrief(
            petName: petName,
            context: petContext,
          ),
          generatedAt: DateTime.now(),
          provider: AiProvider.local,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final PetContext? petContext = care.context;
    final List<CareAnomaly> anomalies = care.anomalies;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.navy.withValues(alpha: 0.06),
            AppColors.sky.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.16)),
      ),
      padding: const EdgeInsets.all(AppTheme.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Text(
                  'AI Care Insight',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: petContext == null
                      ? null
                      : () => _generate(petContext, care.pet.name, force: true),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  tooltip: 'Generate a new insight',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMd),

          if (_loading && _insight == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.gapSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBox(height: 13),
                  SizedBox(height: AppTheme.gapSm),
                  SkeletonBox(height: 13),
                  SizedBox(height: AppTheme.gapSm),
                  SkeletonBox(height: 13, width: 180),
                ],
              ),
            )
          else if (_insight != null)
            Text(
              _insight!.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            )
          else if (!AppConfig.aiConfigured)
            Text(
              'AI features are not configured in this build. Your care records '
              'and statistics still work normally.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Text(
              'Preparing today\'s insight for ${care.pet.name}…',
              style: Theme.of(context).textTheme.bodySmall,
            ),

          // Anomalies come from the deterministic analytics layer, so they are
          // shown whether or not the model responded.
          if (anomalies.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTheme.gapLg),
            _AnomalyBanner(anomaly: anomalies.first),
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapMd),
            Row(
              children: <Widget>[
                const Icon(Icons.cloud_off_rounded,
                    size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Showing an on-device summary — $_error',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ],

          if (_insight != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapMd),
            Row(
              children: <Widget>[
                Icon(
                  _insight!.provider == AiProvider.local
                      ? Icons.phone_android_rounded
                      : Icons.cloud_done_rounded,
                  size: 13,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 5),
                Text(
                  _insight!.provider.label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (_insight!.latencyMs != null && _insight!.latencyMs! > 0) ...<Widget>[
                  Text(
                    ' · ${_insight!.latencyMs}ms',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AnomalyBanner extends StatelessWidget {
  const _AnomalyBanner({required this.anomaly});

  final CareAnomaly anomaly;

  @override
  Widget build(BuildContext context) {
    final Color color = anomaly.severity == AnomalySeverity.watch
        ? AppColors.warning
        : AppColors.info;

    return Container(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_rounded, size: 16, color: color),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(
                  anomaly.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 13.5),
                ),
              ),
              AppPill(
                label: '${(anomaly.confidence * 100).round()}% signal',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            anomaly.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
