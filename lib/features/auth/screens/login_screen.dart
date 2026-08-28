import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/state_views.dart';
import '../auth_controller.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final AuthController auth = context.read<AuthController>();
    await auth.signIn(email: _email.text, password: _password.text);
    // On success the auth gate swaps this screen out; on failure the error is
    // rendered from controller state, so there is nothing to do here.
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.gapXl,
                vertical: AppTheme.gapXxl,
              ),
              child: ConstrainedBox(
                // Keeps the form readable on tablets and landscape.
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const PetMateWordmark(markSize: 92),
                      const SizedBox(height: AppTheme.gapXxl),

                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTheme.gapXs),
                      Text(
                        'Sign in to continue caring for your pets.',
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
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: AppTheme.gapLg),

                      TextFormField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[AutofillHints.password],
                        enabled: !auth.busy,
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
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Please enter your password.' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: auth.busy
                              ? null
                              : () {
                                  auth.clearError();
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ForgotPasswordScreen(
                                        initialEmail: _email.text.trim(),
                                      ),
                                    ),
                                  );
                                },
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: AppTheme.gapSm),

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
                            : const Text('Sign In'),
                      ),
                      const SizedBox(height: AppTheme.gapXl),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            'New to PetMate?',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: auth.busy
                                ? null
                                : () {
                                    auth.clearError();
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    );
                                  },
                            child: const Text('Create an account'),
                          ),
                        ],
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
