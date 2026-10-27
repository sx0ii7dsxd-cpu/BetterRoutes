import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color jetBlack = Color(0xFF050505);
  static const Color royalAmethyst = Color(0xFF3B0A6B);
  static const Color electricCyan = Color(0xFF00E5FF);

  static const Color surface = Color(0xFF111014);
  static const Color text = Color(0xFFF7F5FC);
  static const Color mutedText = Color(0xFFB5AEC5);
  static const Color error = Color(0xFFFF6B6B);
}

abstract final class AppTheme {
  static ThemeData get dark {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: AppColors.royalAmethyst,
      onPrimary: AppColors.electricCyan,
      secondary: AppColors.electricCyan,
      onSecondary: AppColors.jetBlack,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.error,
      onError: AppColors.jetBlack,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.jetBlack,
      canvasColor: AppColors.jetBlack,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.jetBlack,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.mutedText),
        hintStyle: const TextStyle(color: AppColors.mutedText),
        prefixIconColor: AppColors.electricCyan,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.electricCyan,
            width: 1.5,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.electricCyan,
      ),
    );
  }
}
