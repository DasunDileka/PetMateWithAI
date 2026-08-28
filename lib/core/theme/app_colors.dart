import 'package:flutter/material.dart';

/// PetMate brand palette.
///
/// Every value here was sampled directly from the supplied PetMate logo so the
/// interface and the brand mark stay visually consistent:
///   navy wordmark  #234369      golden retriever  #FAD17F / #B97840
///   feeding bowl   #7AC4E9      leash             #84BB7A
///   health heart   #D85E69      paper             #F9FDFE
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------- brand
  /// Sampled from the "PetMate" wordmark.
  static const Color navy = Color(0xFF234369);
  static const Color navyDark = Color(0xFF162C47);
  static const Color navyLight = Color(0xFF3B6394);

  /// Sampled from the retriever illustration.
  static const Color gold = Color(0xFFE8A33D);
  static const Color goldLight = Color(0xFFFAD17F);
  static const Color goldDark = Color(0xFFB97840);

  /// Sampled from the feeding bowl.
  static const Color sky = Color(0xFF7AC4E9);

  /// Sampled from the leash.
  static const Color leaf = Color(0xFF5D9B52);

  /// Sampled from the health heart.
  static const Color coral = Color(0xFFD85E69);

  // ------------------------------------------------------------- surfaces
  static const Color paper = Color(0xFFF7FAFD);
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE2E9F1);

  static const Color ink = Color(0xFF16233A);
  static const Color inkMuted = Color(0xFF5C6B82);
  static const Color inkFaint = Color(0xFF8B99AD);

  // ------------------------------------------------------- dark surfaces
  static const Color paperDark = Color(0xFF0F1725);
  static const Color cardDark = Color(0xFF1A2436);
  static const Color lineDark = Color(0xFF2B3A50);

  // ------------------------------------------------------------- status
  static const Color success = Color(0xFF3F8F52);
  static const Color warning = Color(0xFFD98A20);
  static const Color danger = Color(0xFFC4485A);
  static const Color info = Color(0xFF3E86C4);

  // ------------------------------------------------- care-domain accents
  // Each care module owns a colour so the dashboard, calendar and history
  // are readable at a glance without relying on icons alone.
  static const Color feeding = Color(0xFFE8913D);
  static const Color exercise = Color(0xFF5D9B52);
  static const Color medicine = Color(0xFF6C63B5);
  static const Color vaccination = Color(0xFF3E86C4);
  static const Color grooming = Color(0xFF2FA8A0);
  static const Color vet = Color(0xFFC4485A);

  /// Tint used behind a care accent (12% over white) for chips and icon tiles.
  static Color tint(Color base) => Color.alphaBlend(base.withValues(alpha: 0.12), card);
}
