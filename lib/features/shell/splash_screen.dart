import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/brand.dart';

/// Shown while Firebase restores the session.
///
/// Deliberately not a timed splash: it is displayed exactly as long as the auth
/// state is genuinely unknown, so a returning user with a cached session lands
/// on the dashboard almost immediately rather than waiting out an artificial
/// delay.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.88,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const PetMateWordmark(markSize: 104),
                    const SizedBox(height: AppTheme.gapXxl + AppTheme.gapLg),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
