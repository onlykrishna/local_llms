import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Brand
  static const primary     = Color(0xFF00ADFF);
  static const primaryDark = Color(0xFF0089CC);
  static const secondary   = Color(0xFF03DAC6);

  // Light mode surfaces
  static const surfaceLight = Color(0xFFF8F9FE);
  static const cardLight    = Color(0xFFFFFFFF);
  static const borderLight  = Color(0xFFE0E0E0);

  // Dark mode surfaces
  static const surfaceDark  = Color(0xFF121212);
  static const cardDark     = Color(0xFF1E1E1E);
  static const borderDark   = Color(0xFF2C2C2C);

  // Semantic
  static const error   = Color(0xFFFF4444);
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFC107);

  // Chat bubbles
  static const userBubble    = Color(0xFF00ADFF);
  static const aiBubbleLight = Color(0xFFF0F8FF);
  static const aiBubbleDark  = Color(0xFFF0F8FF); // Force light look in both
  static const errorBubble   = Color(0xFFFFEBEB);

  // Citation card
  static const citationLight = Color(0xFFF5F5FF);
  static const citationDark  = Color(0xFF252535);
}

class AppTextStyles {
  AppTextStyles._();

  static const displayLarge = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5,
  );
  static const headline = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w600,
  );
  static const title = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.5,
  );
  static const caption = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5,
  );
}

class AppSpacing {
  AppSpacing._();

  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 16.0;
  static const lg  = 24.0;
  static const xl  = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  AppRadius._();

  static const sm   = Radius.circular(8);
  static const md   = Radius.circular(12);
  static const lg   = Radius.circular(16);
  static const xl   = Radius.circular(24);
  static const full = Radius.circular(999);
}

class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme(Color textColor) {
    final base = TextTheme(
      displayLarge:   AppTextStyles.displayLarge.copyWith(color: textColor),
      headlineMedium: AppTextStyles.headline.copyWith(color: textColor),
      titleMedium:    AppTextStyles.title.copyWith(color: textColor),
      bodyMedium:     AppTextStyles.body.copyWith(color: textColor),
      bodySmall:      AppTextStyles.caption.copyWith(color: textColor),
      labelSmall:     AppTextStyles.label.copyWith(color: textColor),
    );
    return GoogleFonts.interTextTheme(base);
  }

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
      primary: AppColors.primary,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      textTheme: _buildTextTheme(const Color(0xFF1A1A2E)),
      cardTheme: CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.md),
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardLight,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        color: AppColors.borderLight,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.surfaceDark,
      primary: AppColors.primary,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceDark,
      textTheme: _buildTextTheme(const Color(0xFFE8E8F0)),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFFE8E8F0),
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.md),
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        color: AppColors.borderDark,
      ),
    );
  }
}
