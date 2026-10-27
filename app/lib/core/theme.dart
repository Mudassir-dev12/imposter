import 'package:flutter/material.dart';

/// Dark, vibrant theme for the Impostor game.
class AppTheme {
  static const Color background = Color(0xFF0F111A);
  static const Color surface = Color(0xFF1A1D2B);
  static const Color surfaceElevated = Color(0xFF24293D);
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryLight = Color(0xFFA29BFE);

  // Faction Colors
  static const Color crewColor = Color(0xFF00B894);
  static const Color crewBackground = Color(0xFF003B2F);
  static const Color impostorColor = Color(0xFFFF4757);
  static const Color impostorBackground = Color(0xFF4A0F15);

  static const Color accent = Color(0xFFFFA502);
  static const Color textPrimary = Color(0xFFF1F2F6);
  static const Color textSecondary = Color(0xFFA4B0BE);
  static const Color border = Color(0xFF2F3542);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: impostorColor,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          elevation: 2,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
    );
  }
}
