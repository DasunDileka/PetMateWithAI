import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../shared/models/ai_models.dart';
import '../../shared/models/app_user.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/ui_kit.dart';
import '../ai/ai_service.dart';
import '../ai/chat_repository.dart';
import '../auth/auth_controller.dart';
import '../pets/pet_controller.dart';
import 'demo_data_screen.dart';

/// Profile, notification preferences, privacy controls and diagnostics.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  NotificationPreferences _prefs = NotificationService.instance.preferences;
  bool _notificationsAllowed = false;

  @override
  void initState() {
    super.initState();
    _notificationsAllowed = NotificationService.instance.permissionGranted;
    // The cached value is false on every fresh launch, so confirm the real
    // state with the platform before telling the user permission is missing.
    NotificationService.instance.refreshPermissionStatus().then((bool granted) {
      if (mounted) setState(() => _notificationsAllowed = granted);
    });

    final String? uid = context.read<AuthController>().uid;
    if (uid != null) {
      NotificationService.instance
          .loadPreferences(uid)
          .then((NotificationPreferences prefs) {
        if (mounted) setState(() => _prefs = prefs);
      });
    }
  }

  /// Applies a preference change and persists it.
  ///
  /// The switches used to be pure UI: they moved local state, were discarded
  /// when the screen closed, and nothing consulted them when reminders were
  /// scheduled. Saving through the service is what makes them mean something.
  void _setPrefs(NotificationPreferences next) {
    setState(() => _prefs = next);
    final String? uid = context.read<AuthController>().uid;
    if (uid != null) {
      NotificationService.instance.savePreferences(uid, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final PetController pets = context.watch<PetController>();
    final AppUser? profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          children: <Widget>[
            // ------------------------------------------------------ identity
            AppCard(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      profile?.initials ?? '?',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.gapLg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          profile?.displayName ?? 'Pet Owner',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile?.email ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        AppPill(
                          label: '${pets.pets.length} pet'
                              '${pets.pets.length == 1 ? '' : 's'}',
                          color: AppColors.gold,
                          icon: Icons.pets_rounded,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _editName(context, auth),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit name',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // ------------------------------------------------- notifications
            SectionHeader(
              title: 'Notifications',
              subtitle: 'Choose which reminders PetMate sends',
              icon: Icons.notifications_active_outlined,
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  if (!_notificationsAllowed)
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.gapLg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              // Keeps the sentence clear of the button instead
                              // of running underneath it.
                              padding: const EdgeInsets.only(
                                right: AppTheme.gapMd,
                              ),
                              child: Text(
                                'Reminders are off until notification '
                                'permission is granted.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () async {
                              final bool granted = await NotificationService
                                  .instance
                                  .requestPermission();
                              if (!context.mounted) return;
                              setState(() => _notificationsAllowed = granted);
                              showAppSnack(
                                context,
                                granted
                                    ? 'Notifications enabled'
                                    : 'Notifications were not allowed',
                                isError: !granted,
                              );
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.gapLg),
                            ),
                            child: const Text('Allow'),
                          ),
                        ],
                      ),
                    ),
                  _prefSwitch(
                    'Feeding reminders',
                    'When a scheduled meal is due',
                    _prefs.feeding,
                    (v) => _setPrefs(_prefs.copyWith(feeding: v)),
                  ),
                  _prefSwitch(
                    'Medication reminders',
                    'When a dose is due',
                    _prefs.medicine,
                    (v) => _setPrefs(_prefs.copyWith(medicine: v)),
                  ),
                  _prefSwitch(
                    'Vaccination reminders',
                    'Five days before a due date',
                    _prefs.vaccination,
                    (v) => _setPrefs(_prefs.copyWith(vaccination: v)),
                  ),
                  _prefSwitch(
                    'Grooming reminders',
                    'The day before a task is due',
                    _prefs.grooming,
                    (v) => _setPrefs(_prefs.copyWith(grooming: v)),
                  ),
                  _prefSwitch(
                    'Appointment reminders',
                    'The day before a vet visit',
                    _prefs.appointments,
                    (v) => _setPrefs(_prefs.copyWith(appointments: v)),
                  ),
                  _prefSwitch(
                    'Care insights',
                    'When PetMate notices an unusual pattern',
                    _prefs.insights,
                    (v) => _setPrefs(_prefs.copyWith(insights: v)),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapMd),
            OutlinedButton.icon(
              onPressed: () async {
                await NotificationService.instance.showTestNotification();
                if (context.mounted) {
                  showAppSnack(context, 'Test notification sent');
                }
              },
              icon: const Icon(Icons.notifications_outlined, size: 19),
              label: const Text('Send a test notification'),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // ------------------------------------------------------- privacy
            SectionHeader(
              title: 'Privacy & data',
              icon: Icons.shield_outlined,
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Your pets and records are stored in your own account and '
                    'are not visible to any other user. Only pet-care facts are '
                    'sent to the AI provider — never your name, email or account '
                    'identifiers.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppTheme.gapLg),
                  OutlinedButton.icon(
                    onPressed: () => _clearChats(context, auth),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                    label: const Text('Delete all AI conversations'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // --------------------------------------------------- diagnostics
            SectionHeader(
              title: 'AI configuration',
              subtitle: 'Which provider serves this build',
              icon: Icons.auto_awesome_outlined,
            ),
            _AiDiagnostics(uid: auth.uid),
            const SizedBox(height: AppTheme.gapXl),

            // ---------------------------------------------------- demo data
            SectionHeader(title: 'Demonstration', icon: Icons.science_outlined),
            AppCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DemoDataScreen()),
              ),
              child: Row(
                children: <Widget>[
                  const CareIconTile(
                    icon: Icons.auto_fix_high_rounded,
                    color: AppColors.gold,
                    size: 38,
                  ),
                  const SizedBox(width: AppTheme.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Sample data',
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          'Load two example pets with realistic care history',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.inkFaint),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            // --------------------------------------------------------- about
            AppCard(
              child: Column(
                children: <Widget>[
                  const PetMateWordmark(markSize: 62),
                  const SizedBox(height: AppTheme.gapMd),
                  Text(
                    'Version ${AppConfig.appVersion}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppTheme.gapSm),
                  Text(
                    'PetMate is a care-tracking assistant. It does not provide '
                    'veterinary diagnosis or treatment advice.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),

            OutlinedButton.icon(
              onPressed: () => _signOut(context, auth),
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
            const SizedBox(height: AppTheme.gapXxl),
          ],
        ),
      ),
    );
  }

  Widget _prefSwitch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    bool last = false,
  }) {
    return Column(
      children: <Widget>[
        SwitchListTile(
          value: value,
          onChanged: onChanged,
          title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
          subtitle:
              Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gapLg,
            vertical: 2,
          ),
        ),
        if (!last) const Divider(height: 1, indent: AppTheme.gapLg),
      ],
    );
  }

  Future<void> _editName(BuildContext context, AuthController auth) async {
    final TextEditingController controller =
        TextEditingController(text: auth.profile?.displayName ?? '');
    final GlobalKey<FormState> key = GlobalKey<FormState>();

    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Edit name'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: Validators.name,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final String name = controller.text.trim();
    controller.dispose();

    if (save != true) return;
    final bool ok = await auth.updateDisplayName(name);
    if (!context.mounted) return;
    showAppSnack(
      context,
      ok ? 'Name updated' : (auth.error ?? 'Could not update name'),
      isError: !ok,
    );
  }

  Future<void> _clearChats(BuildContext context, AuthController auth) async {
    final String? uid = auth.uid;
    if (uid == null) return;

    final bool ok = await confirmAction(
      context,
      title: 'Delete all conversations?',
      message:
          'Every AI conversation will be permanently deleted. Your pets and '
          'care records are not affected.',
      confirmLabel: 'Delete all',
    );
    if (!ok || !context.mounted) return;

    await ChatRepository(uid).deleteAllSessions();
    if (context.mounted) showAppSnack(context, 'Conversations deleted');
  }

  Future<void> _signOut(BuildContext context, AuthController auth) async {
    final bool ok = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access your pets.',
      confirmLabel: 'Sign out',
      destructive: false,
    );
    if (!ok) return;

    // Cancel scheduled reminders so a different account on the same device does
    // not receive the previous owner's pet notifications.
    await NotificationService.instance.cancelAll();

    // Leave this screen *before* ending the session. This one is a pushed
    // route that watches the pet-scoped providers, so staying mounted while
    // those are released is exactly the situation that produces a
    // missing-provider error. `_SignedInScope` also unwinds the stack as a
    // safety net for sign-outs that do not originate here (an expired or
    // revoked token, for instance) — doing it here as well simply makes the
    // transition immediate rather than a frame late.
    if (context.mounted) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    }

    await auth.signOut();
  }
}

class _AiDiagnostics extends StatelessWidget {
  const _AiDiagnostics({required this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox.shrink();

    final AiService service = AiService(uid: uid!);
    final List<AiProvider> providers = service.availableProviders;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (providers.isEmpty)
            Text(
              'No AI provider is configured in this build. PetMate falls back to '
              'on-device statistics, so insights still work — they are just not '
              'written in natural language.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else ...<Widget>[
            Text(
              'Requests try each provider in order and stop at the first '
              'success.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.gapMd),
            ...providers.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${entry.key + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.gapMd),
                      Expanded(
                        child: Text(
                          entry.value.label,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      AppPill(
                        label: entry.key == 0 ? 'Primary' : 'Fallback',
                        color: entry.key == 0
                            ? AppColors.success
                            : AppColors.inkFaint,
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              'Model: ${AppConfig.geminiModel}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
