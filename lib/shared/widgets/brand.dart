import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Asset paths for the supplied PetMate brand mark.
class BrandAssets {
  const BrandAssets._();

  /// Full lockup: illustration, wordmark and tagline.
  static const String logo = 'assets/images/petmate_logo.png';

  /// Illustration only, with a transparent background so it sits on any colour.
  static const String mark = 'assets/images/petmate_mark.png';

  /// Square crop used for the launcher icon.
  static const String icon = 'assets/images/petmate_icon.png';
}

/// The PetMate illustration on its own, sized and optionally elevated.
class PetMateMark extends StatelessWidget {
  const PetMateMark({super.key, this.size = 72, this.elevated = false});

  final double size;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      BrandAssets.mark,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // The mark is decorative wherever it appears beside the product name.
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
    );

    if (!elevated) return image;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: image,
      ),
    );
  }
}

/// Mark plus wordmark, used on the splash, login and register screens.
class PetMateWordmark extends StatelessWidget {
  const PetMateWordmark({
    super.key,
    this.markSize = 96,
    this.showTagline = true,
    this.color,
  });

  final double markSize;
  final bool showTagline;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = color ?? AppColors.navy;

    return Semantics(
      label: '${AppConfig.appName}. ${AppConfig.appTagline}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PetMateMark(size: markSize, elevated: true),
          const SizedBox(height: AppTheme.gapLg),
          Text(
            AppConfig.appName,
            style: TextStyle(
              fontSize: markSize * 0.40,
              fontWeight: FontWeight.w800,
              color: titleColor,
              letterSpacing: -1.0,
              height: 1.0,
            ),
          ),
          if (showTagline) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Text(
              AppConfig.appTagline,
              style: TextStyle(
                fontSize: markSize * 0.145,
                fontWeight: FontWeight.w500,
                color: titleColor.withValues(alpha: 0.72),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Soft brand gradient used behind auth screens and the splash.
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? <Color>[
                  AppColors.paperDark,
                  const Color(0xFF152033),
                ]
              : <Color>[
                  const Color(0xFFEAF3FB),
                  AppColors.paper,
                ],
        ),
      ),
      child: child,
    );
  }
}

/// Circular pet avatar with a graceful fallback when there is no photo.
class PetAvatar extends StatelessWidget {
  const PetAvatar({
    super.key,
    this.photoUrl,
    required this.fallbackEmoji,
    this.size = 56,
  });

  final String? photoUrl;
  final String fallbackEmoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? url = photoUrl;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.tint(AppColors.gold),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                fallbackEmoji,
                style: TextStyle(fontSize: size * 0.46),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              // A broken or expired photo URL must never blank the row it is in.
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  fallbackEmoji,
                  style: TextStyle(fontSize: size * 0.46),
                ),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: size * 0.35,
                    height: size * 0.35,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
    );
  }
}
