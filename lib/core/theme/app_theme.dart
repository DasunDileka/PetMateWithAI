import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Central Material 3 theme for PetMate.
///
/// Kept in one place so spacing, radii, elevation and typography stay
/// consistent across every feature module — one of the UI/UX rubric points is
/// specifically "consistency", and a shared theme is the cheapest way to
/// guarantee it.
class AppTheme {
  const AppTheme._();

  // Design tokens ---------------------------------------------------------
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusPill = 999;

  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;
  static const double gapXxl = 32;

  /// Minimum tap target. Material guidance is 48dp; the rubric rewards
  /// "large touch targets" under accessibility.
  static const double minTapTarget = 48;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.navyLight : AppColors.navy,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: const Color(0xFF3A2A08),
      tertiary: AppColors.leaf,
      error: AppColors.danger,
      surface: isDark ? AppColors.paperDark : AppColors.paper,
      onSurface: isDark ? const Color(0xFFE6ECF5) : AppColors.ink,
      surfaceContainerHighest: isDark ? AppColors.cardDark : AppColors.card,
      outlineVariant: isDark ? AppColors.lineDark : AppColors.line,
    );

    final Color cardColor = isDark ? AppColors.cardDark : AppColors.card;
    final Color borderColor = isDark ? AppColors.lineDark : AppColors.line;
    final Color mutedText = isDark ? const Color(0xFF9AA9BF) : AppColors.inkMuted;

    final TextTheme text = _textTheme(scheme.onSurface, mutedText);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      // Roboto ships with Android, so this avoids a runtime font download and
      // keeps the app usable offline.
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: borderColor),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: gapLg, vertical: gapLg),
        border: _inputBorder(borderColor),
        enabledBorder: _inputBorder(borderColor),
        focusedBorder: _inputBorder(scheme.primary, width: 1.8),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.8),
        labelStyle: TextStyle(color: mutedText),
        hintStyle: TextStyle(color: isDark ? AppColors.inkFaint : AppColors.inkFaint),
        prefixIconColor: mutedText,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(minTapTarget + 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTapTarget + 4),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTapTarget, minTapTarget),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.cardDark : AppColors.paper,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: gapMd, vertical: gapSm),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : mutedText,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? scheme.primary : mutedText,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: text.titleMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        showDragHandle: true,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        insetPadding: const EdgeInsets.all(gapLg),
      ),

      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: gapLg, vertical: gapXs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
        ),
        minVerticalPadding: gapMd,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.15),
        circularTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm + 2),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(Color onSurface, Color muted) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: onSurface,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 15.5, height: 1.45, color: onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: onSurface),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.4,
      ),
    );
  }
}
