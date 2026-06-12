import 'package:flutter/material.dart';

/// Palette MED — thème sombre type "réseau de nuit".
abstract final class MedColors {
  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF131B2E);
  static const surface2 = Color(0xFF1E2940);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF28C00);
  static const busGrey = Color(0xFF475774);
  static const text = Color(0xFFEFF3FC);
  static const secondary = Color(0xFF8A94A8);
  static const dividerColor = Color(0xFF263149);

  // Couleurs officielles des lignes (échantillon V0).
  static const m1 = Color(0xFFFFCE00);
  static const m4 = Color(0xFFBB4D98);
  static const m12 = Color(0xFF007E49);
  static const m13 = Color(0xFF98D4E2);
  static const m14 = Color(0xFF62259D);
}

ThemeData buildMedTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: MedColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: MedColors.accent,
      surface: MedColors.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: MedColors.text,
      displayColor: MedColors.text,
    ),
  );
}
