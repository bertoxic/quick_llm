import 'package:flutter/material.dart';

class AppColors {
  static const porcelain = Color(0xFFF5F5F5);
  static const teal = Color(0xFF76ABAE);
  static const charcoal = Color(0xFF303841);
  static const orange = Color(0xFFFF5722);

  static const ink = Color(0xFF111315);
  static const rail = Color(0xFF0D0F10);
  static const panel = Color(0xFF23282D);
  static const panelSoft = Color(0xFF2B3035);
  static const line = Color(0xFFE1E4E6);
  static const muted = Color(0xFF778087);
  static const softOrange = Color(0xFFFFE8DF);
  static const softTeal = Color(0xFFE4F0F1);
  static const surfaceDisabled = Color(0xFFDADDE0);
}

class AppTheme {
  static ThemeData get theme => lightTheme;

  static ThemeData get lightTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.orange,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.orange,
      onPrimary: Colors.white,
      primaryContainer: AppColors.softOrange,
      onPrimaryContainer: AppColors.charcoal,
      secondary: AppColors.teal,
      onSecondary: AppColors.charcoal,
      secondaryContainer: AppColors.softTeal,
      onSecondaryContainer: AppColors.charcoal,
      surface: Colors.white,
      onSurface: AppColors.charcoal,
      surfaceContainer: const Color(0xFFFAFAFA),
      surfaceContainerHigh: const Color(0xFFF1F3F4),
      surfaceContainerHighest: const Color(0xFFEDEFF0),
      outline: const Color(0xFFD1D5D8),
      outlineVariant: AppColors.line,
      error: AppColors.orange,
      shadow: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: AppColors.porcelain,
      fontFamily: 'Arial',
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: AppColors.charcoal,
            displayColor: AppColors.charcoal,
            fontFamily: 'Arial',
          ),
      iconTheme: const IconThemeData(color: AppColors.charcoal),
      dividerColor: AppColors.line,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.softOrange,
        disabledColor: AppColors.surfaceDisabled,
        side: const BorderSide(color: AppColors.line),
        labelStyle: const TextStyle(
          color: AppColors.charcoal,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.charcoal,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.charcoal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.teal.withOpacity(0.55)),
        radius: const Radius.circular(4),
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.orange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.orange,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF5B2618),
      onPrimaryContainer: Colors.white,
      secondary: AppColors.teal,
      onSecondary: AppColors.ink,
      secondaryContainer: const Color(0xFF294D50),
      onSecondaryContainer: Colors.white,
      surface: const Color(0xFF20272C),
      onSurface: AppColors.porcelain,
      surfaceContainer: const Color(0xFF252D32),
      surfaceContainerHigh: const Color(0xFF2B3439),
      surfaceContainerHighest: const Color(0xFF344046),
      outline: const Color(0xFF4A555B),
      outlineVariant: const Color(0xFF3B464C),
      error: AppColors.orange,
      shadow: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: AppColors.charcoal,
      fontFamily: 'Arial',
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: AppColors.porcelain,
            displayColor: AppColors.porcelain,
            fontFamily: 'Arial',
          ),
      iconTheme: const IconThemeData(color: AppColors.porcelain),
      dividerColor: const Color(0xFF3B464C),
      cardTheme: CardThemeData(
        color: const Color(0xFF252D32),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF252D32),
        selectedColor: const Color(0xFF5B2618),
        disabledColor: const Color(0xFF3A4247),
        side: const BorderSide(color: Color(0xFF3B464C)),
        labelStyle: const TextStyle(
          color: AppColors.porcelain,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252D32),
        hintStyle: const TextStyle(color: Color(0xFFB3BEC3), fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3B464C)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3B464C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.porcelain,
          side: const BorderSide(color: Color(0xFF3B464C)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.porcelain,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.teal.withOpacity(0.65)),
        radius: const Radius.circular(4),
      ),
    );
  }
}
