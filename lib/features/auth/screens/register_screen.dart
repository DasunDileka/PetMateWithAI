import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/state_views.dart';
import '../auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final AuthController auth = context.read<AuthController>();
    final bool ok = await auth.register(
      name: _name.text,
      email: _email.text,
      password: _password.text,
    );

    // A successful registration signs the user straight in, so the auth gate
    // replaces the whole navigation stack; popping first avoids leaving this
    // screen underneath it.
    if (ok && mounted) Navigator.of(context).pop();
  }

  /// Simple strength signal. Advisory only — the actual minimum is enforced by
  /// [Validators.password] and by Firebase.
  ({double value, String label, Color color}) _strength(String password) {
    int score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;

    return switch (score) {
      0 || 1 => (value: 0.25, label: 'Weak', color: const Color(0xFFC4485A)),
      2 || 3 => (value: 0.6, label: 'Fair', color: const Color(0xFFD98A20)),
      _ => (value: 1.0, label: 'Strong', color: const Color(0xFF3F8F52)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final ({double value, String label, Color color}) strength =
        _strength(_password.text);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: auth.busy ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.gapXl,
                vertical: AppTheme.gapLg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Center(child: PetMateMark(size: 76, elevated: true)),
                      const SizedBox(height: AppTheme.gapXl),

                      Text(
                        'Create your account',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.gapXs),
                      Text(
                        'Start tracking your pet\'s care in a few taps.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.gapXl),

                      if (auth.error != null) ...<Widget>[
                        InlineNotice(
                          message: auth.error!,
                          icon: Icons.error_outline_rounded,
                          color: Theme.of(context).colorScheme.error,
                          onDismiss: auth.clearError,
                        ),
                        const SizedBox(height: AppTheme.gapLg),
                      ],

                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.name],
                        enabled: !auth.busy,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: Validators.name,
                      ),
                      const SizedBox(height: AppTheme.gapLg),

                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.email],
                        enabled: !auth.busy,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: AppTheme.gapLg),

                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.newPassword],
                        enabled: !auth.busy,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                          ),
                        ),
                        validator: Validators.password,
                      ),

                      if (_password.text.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppTheme.gapSm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: strength.value,
                                  minHeight: 5,
                                  backgroundColor:
                                      strength.color.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      strength.color),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.gapMd),
                            Text(
                              strength.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: strength.color,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppTheme.gapLg),

                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        enabled: !auth.busy,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                        ),
                        validator: (v) =>
                            Validators.confirmPassword(v, _password.text),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: AppTheme.gapXl),

                      FilledButton(
                        onPressed: auth.busy ? null : _submit,
                        child: auth.busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Account'),
                      ),
                      const SizedBox(height: AppTheme.gapLg),

                      Text(
                        'Your pet records are private to your account and are '
                        'never shared with other users.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
