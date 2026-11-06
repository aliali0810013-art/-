import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const navy = Color(0xFF0A2540);
  static const navy2 = Color(0xFF0D2C54);
  static const navy3 = Color(0xFF113C69);
  static const gold = Color(0xFFE5A93C);
  static const gold2 = Color(0xFFF5B041);
  static const background = Color(0xFFF4F7FA);
  static const surface = Colors.white;
  static const text = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const green = Color(0xFF16803B);
  static const red = Color(0xFFC62828);
  static const blue = Color(0xFF1659A7);
  static const purple = Color(0xFF6330B5);
  static const mint = Color(0xFFE8F8F0);
  static const sky = Color(0xFFEAF4FC);
  static const rose = Color(0xFFFDEDEC);
  static const cream = Color(0xFFFFF8E7);
}

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy2,
        brightness: Brightness.light,
        primary: AppColors.navy2,
        secondary: AppColors.gold,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerColor: const Color(0xFFE5EAF0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E1EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E1EA)),
        ),
      ),
    );
  }
}
