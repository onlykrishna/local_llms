import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'aetheric_glow_extension.dart';

class AppTheme {
  // --- Ethereal Intelligence Tokens (Dark) ---
  static const Color dSurface = Color(0xFF14121B);
  static const Color dSurfaceContainer = Color(0xFF211E28);
  static const Color dOnSurface = Color(0xFFE6E0EE);
  static const Color dOnSurfaceVariant = Color(0xFFCBC3D9);
  
  // --- Aetheric Intelligence Tokens (Light) ---
  static const Color lSurface = Color(0xFFF9F7FF);
  static const Color lSurfaceContainer = Color(0xFFF1EEFA);
  static const Color lOnSurface = Color(0xFF14121B);
  static const Color lOnSurfaceVariant = Color(0xFF494456);

  // --- Shared Branding ---
  static const Color primary = Color(0xFF5D38BB); // Unified Branding Purple
  static const Color accent = Color(0xFFCEBDFF);
  static const Color tertiary = Color(0xFF00E475);
  static const Color error = Color(0xFFFFB4AB);

  static final ThemeData darkTheme = _buildTheme(Brightness.dark);
  static final ThemeData lightTheme = _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color resolvedSurface = isDark ? dSurface : lSurface;
    final Color resolvedOnSurface = isDark ? dOnSurface : lOnSurface;
    final Color resolvedContainer = isDark ? dSurfaceContainer : lSurfaceContainer;
    final Color resolvedOnVariant = isDark ? dOnSurfaceVariant : lOnSurfaceVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [
        AethericGlowExtension(
          glassSurface: isDark 
              ? Colors.white.withOpacity(0.04) 
              : Colors.black.withOpacity(0.03),
          glassStroke: isDark 
              ? Colors.white.withOpacity(0.08) 
              : Colors.black.withOpacity(0.05),
        ),
      ],
      colorScheme: ColorScheme(
        brightness: brightness,
        surface: resolvedSurface,
        onSurface: resolvedOnSurface,
        surfaceContainer: resolvedContainer,
        onSurfaceVariant: resolvedOnVariant,
        primary: primary,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.black,
        tertiary: tertiary,
        onTertiary: Colors.white,
        error: error,
        onError: Colors.white,
        outline: isDark ? const Color(0xFF2B2933) : const Color(0xFFE0DAF2),
        outlineVariant: isDark ? const Color(0xFF494456) : const Color(0xFFCBC3D9),
      ),
      scaffoldBackgroundColor: resolvedSurface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: resolvedOnSurface),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: resolvedOnSurface,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: resolvedContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? const Color(0xFF2B2933) : const Color(0xFFE0DAF2)),
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).copyWith(
        bodyLarge: GoogleFonts.inter(color: resolvedOnSurface, fontSize: 16, height: 1.6),
        bodyMedium: GoogleFonts.inter(color: resolvedOnVariant, fontSize: 14),
        labelSmall: GoogleFonts.inter(color: resolvedOnVariant.withOpacity(0.6), fontSize: 11),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: resolvedContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? const Color(0xFF2B2933) : const Color(0xFFE0DAF2)),
        ),
        hintStyle: TextStyle(color: resolvedOnVariant.withOpacity(0.5)),
      ),
    );
  }
}
