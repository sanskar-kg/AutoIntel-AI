import 'package:flutter/material.dart';

/// Design tokens shared with the MIC app (see docs/UI_DESIGN_SPEC.md).
abstract final class AppColors {
  static const blue = Color(0xFF0068EF);
  static const heading = Color(0xFF11161B);
  static const secondary = Color(0xFF6E767D);
  static const navy = Color(0xFF07143A);
  static const muted = Color(0xFF68758E);
  static const placeholder = Color(0xFFA4ADBD);
  static const border = Color(0xFFD1D5DA);

  /// Secondary text on the pastel tints (muted is too light there for small text).
  static const mutedOnTint = Color(0xFF47536B);
  static const hairline = Color(0xFFE4EAF2);
  static const surfaceAlt = Color(0xFFF8F9FB);
  static const chipBg = Color(0xFFF2F7FD);
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF1E8E3E);
  static const warning = Color(0xFFB26A00);

  // Feature tile tints
  static const tintBlue = Color(0xFFEAF7FF);
  static const tintAmber = Color(0xFFFFF8E9);
  static const tintGreen = Color(0xFFEAFFF3);
  static const tintViolet = Color(0xFFF5F0FF);
  static const tintPink = Color(0xFFFFF0F5);
}

/// Sora text style helper (same signature as MIC's `sora()`).
TextStyle sora(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.heading,
  double? height,
  double? spacing,
}) => TextStyle(
  fontFamily: 'Sora',
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
  height: height,
  letterSpacing: spacing ?? 0,
);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Sora',
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blue,
  ),
  textTheme: ThemeData.light().textTheme.apply(
    fontFamily: 'Sora',
    bodyColor: AppColors.heading,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 48),
      textStyle: sora(14, weight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.blue, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.error, width: 1.6),
    ),
  ),
);
