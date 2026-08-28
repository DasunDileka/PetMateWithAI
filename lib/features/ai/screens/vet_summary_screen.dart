import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/ai_models.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../analytics/care_analytics.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';
import '../ai_service.dart';
import '../pet_context_builder.dart';

/// Pre-appointment summary the owner can review and show to their vet.
///
/// The owner always sees the computed figures alongside the generated prose, so
/// they can verify the summary before handing it to a clinician — the brief
/// asks explicitly for a review step, and an unverifiable summary would be
/// worse than none.
class VetSummaryScreen extends StatefulWidget {
  const VetSummaryScreen({super.key});

  @override
  State<VetSummaryScreen> createState() => _VetSummaryScreenState();
}

class _VetSummaryScreenState extends State<VetSummaryScreen> {
  AiService? _ai;
  AiInsight? _summary;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? uid = context.read<AuthController>().uid;
    if (uid != null && _ai == null) {
      _ai = AiService(uid: uid);
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  Future<void> _generate({bool force = false}) async {
    final CareController care = context.read<CareController>();
    final PetContext? petContext = care.context;
    final AiService? ai = _ai;

    if (ai == null || petContext == null) return;

    if (!ai.isConfigured) {
      setState(() => _error =
          'AI features are not configured in this build. The recorded figures '
          'below are still accurate and can be shown to your vet.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final AiInsight result = await ai.insight(
        petId: care.pet.id,
        kind: AiInsightKind.vetSummary,
        context: petContext,
        petName: care.pet.name,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();
    final PetContext? petContext = care.context;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vet visit summary'),
        actions: <Widget>[
          if (_summary != null)
            IconButton(
              tooltip: 'Copy summary',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: _summary!.text),
                );
                if (context.mounted) {
                  showAppSnack(context, 'Summary copied to clipboard');
                }
              },
            ),
          IconButton(
            tooltip: 'Regenerate',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _generate(force: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: petContext == null
            ? const LoadingView()
            : ListView(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                children: <Widget>[
                  AppCard(
                    accent: AppColors.vet,
                    child: Row(
                      children: <Widget>[
                        const CareIconTile(
                          icon: Icons.description_outlined,
                          color: AppColors.vet,
                        ),
                        const SizedBox(width: AppTheme.gapMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('${care.pet.name}\'s recent care',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              Text(
                                'Review this before showing it to your vet',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.gapXl),

                  // Verified figures come first: these are computed on-device
                  // and are what the model was told.
                  SectionHeader(
                    title: 'Recorded figures',
                    subtitle: 'Computed from your records',
                    icon: Icons.calculate_outlined,
                  ),
                  _FiguresCard(context: petContext, care: care),
                  const SizedBox(height: AppTheme.gapXl),

                  SectionHeader(
                    title: 'Written summary',
                    subtitle: 'Generated from the figures above',
                    icon: Icons.auto_awesome_rounded,
                  ),

                  if (_loading)
                    const AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SkeletonBox(height: 13),
                          SizedBox(height: AppTheme.gapSm),
                          SkeletonBox(height: 13),
                          SizedBox(height: AppTheme.gapSm),
                          SkeletonBox(height: 13),
                          SizedBox(height: AppTheme.gapSm),
                          SkeletonBox(height: 13, width: 200),
                        ],
                      ),
                    )
                  else if (_summary != null)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SelectableText(
                            _summary!.text,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.55),
                          ),
                          const SizedBox(height: AppTheme.gapMd),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.cloud_done_rounded,
                                  size: 13, color: AppColors.inkFaint),
                              const SizedBox(width: 5),
                              Text(
                                '${_summary!.provider.label} · '
                                'generated ${_time(_summary!.generatedAt)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    AppCard(
                      child: Column(
                        children: <Widget>[
                          InlineNotice(message: _error!),
                          const SizedBox(height: AppTheme.gapMd),
                          OutlinedButton.icon(
                            onPressed: () => _generate(force: true),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppTheme.gapXl),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.gapMd),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.info_outline_rounded,
                            size: 17, color: AppColors.warning),
                        const SizedBox(width: AppTheme.gapSm),
                        Expanded(
                          child: Text(
                            'This is a record summary, not a clinical '
                            'assessment. Always confirm the details are correct '
                            'before relying on them.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.gapXl),
                ],
              ),
      ),
    );
  }

  static String _time(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'am' : 'pm'}';
  }
}

class _FiguresCard extends StatelessWidget {
  const _FiguresCard({required this.context, required this.care});

  final PetContext context;
  final CareController care;

  @override
  Widget build(BuildContext buildContext) {
    final CompletionStat feeding = context.feeding;
    final CompletionStat meds = context.medication;
    final TrendResult trend = context.trend;

    return AppCard(
      child: Column(
        children: <Widget>[
          DetailRow(
            label: 'Pet',
            value: '${care.pet.name} · ${care.pet.subtitle}',
            icon: Icons.pets_rounded,
          ),
          const Divider(height: AppTheme.gapLg),
          DetailRow(
            label: 'Feeding',
            value: feeding.hasData
                ? '${feeding.completed} of ${feeding.expected} completed '
                    '(${feeding.percent.round()}%) over 7 days'
                : 'No scheduled feedings recorded',
            icon: Icons.restaurant_rounded,
          ),
          DetailRow(
            label: 'Activity',
            value: trend.hasData
                ? '${trend.mean.round()} min/day average · '
                    '${trend.direction.label.toLowerCase()}'
                : 'No exercise recorded',
            icon: Icons.directions_walk_rounded,
          ),
          DetailRow(
            label: 'Medication',
            value: meds.hasData
                ? '${meds.completed} of ${meds.expected} doses given '
                    '(${meds.percent.round()}%)'
                : 'No doses scheduled in this period',
            icon: Icons.medication_rounded,
          ),
          DetailRow(
            label: 'Vaccinations',
            value: care.vaccinations.isEmpty
                ? 'None recorded'
                : '${care.vaccinations.length} recorded'
                    '${context.snapshot.nextVaccination == null ? '' : ' · next ${context.snapshot.nextVaccination!.dueLabel.toLowerCase()}'}',
            icon: Icons.vaccines_rounded,
          ),
          if (context.anomalies.isNotEmpty) ...<Widget>[
            const Divider(height: AppTheme.gapLg),
            ...context.anomalies.map((CareAnomaly a) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.flag_outlined,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: AppTheme.gapSm),
                      Expanded(
                        child: Text(
                          a.title,
                          style: Theme.of(buildContext).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
