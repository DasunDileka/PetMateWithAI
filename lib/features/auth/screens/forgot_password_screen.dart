import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/state_views.dart';
import '../auth_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);

  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final bool ok = await context.read<AuthController>().sendPasswordReset(
          _email.text,
        );

    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: false,
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.gapXl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _sent ? _confirmation() : _form(auth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(AuthController auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: PetMateMark(size: 68, elevated: true)),
          const SizedBox(height: AppTheme.gapXl),

          Text(
            'Forgot your password?',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.gapSm),
          Text(
            'Enter the email address on your account and we will send you a '
            'link to set a new password.',
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
            textInputAction: TextInputAction.done,
            enabled: !auth.busy,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: Validators.email,
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
                : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }

  Widget _confirmation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 36,
            color: AppColors.success,
          ),
        ).withCenter(),
        const SizedBox(height: AppTheme.gapXl),

        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.gapSm),
        Text(
          'If an account exists for ${_email.text.trim()}, a password reset '
          'link is on its way. Remember to check your spam folder.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.gapXxl),

        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}

extension on Widget {
  /// Centres a fixed-size child inside a stretched column.
  Widget withCenter() => Align(alignment: Alignment.center, child: this);
}
