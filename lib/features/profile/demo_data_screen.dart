import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/ui_kit.dart';
import '../auth/auth_controller.dart';
import '../pets/pet_controller.dart';
import 'demo_data_service.dart';

/// Loads or clears the demonstration dataset.
///
/// Kept behind an explicit screen rather than a hidden debug flag: seeding
/// writes real documents to the signed-in account, so it needs a clear,
/// reversible, confirmed action.
class DemoDataScreen extends StatefulWidget {
  const DemoDataScreen({super.key});

  @override
  State<DemoDataScreen> createState() => _DemoDataScreenState();
}

class _DemoDataScreenState extends State<DemoDataScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _seed() async {
    final AuthController auth = context.read<AuthController>();
    final PetController pets = context.read<PetController>();
    final String? uid = auth.uid;
    if (uid == null) return;

    final bool ok = await confirmAction(
      context,
      title: 'Load sample data?',
      message:
          'This adds two example pets — Bruno (Labrador) and Luna (cat) — with '
          'two weeks of feeding, exercise, medication, vaccination, grooming '
          'and veterinary records to your account.',
      confirmLabel: 'Load',
      destructive: false,
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Creating pets and care records…';
    });

    try {
      final DemoSeedResult result = await DemoDataService(uid).seed();

      pets.selectPet(result.activePetId);
      await auth.setActivePet(result.activePetId);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Sample data loaded. Bruno is now the selected pet.';
      });
      showAppSnack(context, 'Sample data loaded');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      showAppSnack(context, 'Could not load sample data.', isError: true);
    }
  }

  Future<void> _clear() async {
    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return;

    final bool ok = await confirmAction(
      context,
      title: 'Delete all pets and records?',
      message:
          'This permanently removes every pet, care record, appointment and '
          'saved veterinarian in your account. This cannot be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Deleting records…';
    });

    try {
      final int removed = await DemoDataService(uid).clearAll();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Removed $removed pet${removed == 1 ? '' : 's'} and their records.';
      });
      showAppSnack(context, 'All data cleared');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      showAppSnack(context, 'Could not clear the data.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PetController pets = context.watch<PetController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sample data')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          children: <Widget>[
            AppCard(
              accent: AppColors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const CareIconTile(
                        icon: Icons.auto_fix_high_rounded,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppTheme.gapMd),
                      Expanded(
                        child: Text(
                          'Demonstration dataset',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.gapMd),
                  Text(
                    'Two pets with deliberately different profiles, so you can '
                    'see that AI recommendations are personalised rather than '
                    'generic.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapLg),

            _PetPreview(
              emoji: '🐶',
              name: 'Bruno',
              detail: 'Labrador Retriever · 3 years · 18 kg',
              points: const <String>[
                'Two daily meals, 12 of 14 completed this week',
                'Exercise declining: 30 → 12 minutes over five days',
                'Rabies vaccination due in 5 days',
                'Vet appointment tomorrow at 10:30 AM',
                'Bath due in 2 days',
              ],
            ),
            const SizedBox(height: AppTheme.gapMd),
            _PetPreview(
              emoji: '🐱',
              name: 'Luna',
              detail: 'British Shorthair · 9 years · 4.6 kg',
              points: const <String>[
                'Three small meals a day, fully completed',
                'Short, steady indoor play sessions',
                'Daily joint supplement, one dose missed',
                'Nail trim overdue by a day',
              ],
            ),
            const SizedBox(height: AppTheme.gapXl),

            if (_status != null) ...<Widget>[
              AppCard(
                child: Row(
                  children: <Widget>[
                    if (_busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 20, color: AppColors.success),
                    const SizedBox(width: AppTheme.gapMd),
                    Expanded(
                      child: Text(
                        _status!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.gapLg),
            ],

            FilledButton.icon(
              onPressed: _busy ? null : _seed,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Load sample data'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.gold),
            ),
            const SizedBox(height: AppTheme.gapMd),
            OutlinedButton.icon(
              onPressed: _busy || pets.pets.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete all pets and records'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
            const SizedBox(height: AppTheme.gapLg),
            Text(
              'Sample data is written to your own account using the same '
              'security rules as normal records. It is not shared with anyone.',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.gapXl),
          ],
        ),
      ),
    );
  }
}

class _PetPreview extends StatelessWidget {
  const _PetPreview({
    required this.emoji,
    required this.name,
    required this.detail,
    required this.points,
  });

  final String emoji;
  final String name;
  final String detail;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: Theme.of(context).textTheme.titleSmall),
                    Text(detail,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMd),
          ...points.map((String p) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle, size: 5,
                          color: AppColors.inkFaint),
                    ),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: Text(
                        p,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
