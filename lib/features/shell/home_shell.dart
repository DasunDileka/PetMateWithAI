import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/pet.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/state_views.dart';
import '../ai/screens/ai_assistant_screen.dart';
import '../auth/auth_controller.dart';
import '../care/screens/care_hub_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../pets/pet_controller.dart';
import '../pets/screens/pet_form_screen.dart';
import '../pets/screens/pets_screen.dart';
import '../profile/profile_screen.dart';
import '../veterinary/screens/vet_hub_screen.dart';

/// Authenticated app shell: bottom navigation over the pet-scoped data layer.
///
/// The controllers themselves are provided above `MaterialApp`'s Navigator (see
/// `app.dart`), so this widget only *consumes* them. That placement is what
/// lets pushed routes — the care screens, the forms, the profile — resolve the
/// same controller instances instead of crashing on a missing provider.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _restoredActivePet = false;

  @override
  Widget build(BuildContext context) {
    final PetController pets = context.watch<PetController>();
    final AuthController auth = context.watch<AuthController>();

    // Restore the pet the user last worked with, once, after both the pet list
    // and the profile have arrived.
    if (!_restoredActivePet && !pets.loading && auth.profile != null) {
      _restoredActivePet = true;
      final String? uid = auth.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        pets.restoreActivePet(auth.profile!.activePetId);
        // Reminder preferences gate every schedule call, so they have to be in
        // memory before the first care screen can queue anything.
        if (uid != null) NotificationService.instance.loadPreferences(uid);
      });
    }

    if (pets.loading) {
      return const Scaffold(body: LoadingView(message: 'Loading your pets…'));
    }

    if (pets.error != null && pets.pets.isEmpty) {
      return Scaffold(
        body: ErrorView(message: pets.error!, onRetry: pets.clearError),
      );
    }

    final Pet? active = pets.activePet;
    if (active == null) return const NoPetsScreen();

    return Scaffold(
      // IndexedStack keeps each tab's scroll position and form state alive when
      // the user moves between tabs.
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          DashboardScreen(),
          PetsScreen(),
          CareHubScreen(),
          VetHubScreen(),
          AiAssistantScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets_rounded),
            label: 'Pets',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Care',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_hospital_outlined),
            selectedIcon: Icon(Icons.local_hospital_rounded),
            label: 'Vet',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'AI',
          ),
        ],
      ),
    );
  }
}

/// First-run state: the account exists but there are no pets yet.
///
/// Profile and settings are reachable from here as well as from the dashboard —
/// otherwise a brand-new user would be unable to open settings, manage their
/// account, or load the sample dataset without first creating a pet by hand.
class NoPetsScreen extends StatelessWidget {
  const NoPetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gapLg,
                  AppTheme.gapSm,
                  AppTheme.gapSm,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    const PetMateMark(size: 34),
                    const SizedBox(width: AppTheme.gapSm),
                    Text(
                      'PetMate',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.account_circle_outlined, size: 27),
                      tooltip: 'Profile and settings',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTheme.gapXl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const PetMateMark(size: 96, elevated: true),
                        const SizedBox(height: AppTheme.gapXl),
                        Text(
                          'Welcome, ${auth.profile?.firstName ?? 'there'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.gapSm),
                        Text(
                          'You haven\'t added a pet yet. Add your first pet to '
                          'start tracking feeding, exercise, medication and vet '
                          'visits — and to get personalised AI insights.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTheme.gapXxl),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PetFormScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add your first pet'),
                          style: FilledButton.styleFrom(
                            minimumSize:
                                const Size(240, AppTheme.minTapTarget + 4),
                          ),
                        ),
                        const SizedBox(height: AppTheme.gapMd),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ProfileScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 19),
                          label: const Text('Or load sample data'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
