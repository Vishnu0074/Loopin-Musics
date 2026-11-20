import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0D0D0D);
  static const surface = Color(0xFF151515);
  static const surfaceElevated = Color(0xFF1C1C1C);
  static const accent = Colors.pinkAccent;
  static const text = Colors.white;
  static const muted = Colors.white60;
  static const divider = Colors.white10;
}

class AppFonts {
  static const displayFamily = 'Tangerine';
  static const displayFallback = <String>['cursive', 'serif'];

  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: displayFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // Alias for backward compatibility if referenced
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => display(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark);
    final baseTextTheme = Typography.material2021(platform: TargetPlatform.android).white;
    const displayStyle = TextStyle(
      fontFamily: AppFonts.displayFamily,
      fontFamilyFallback: AppFonts.displayFallback,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme.copyWith(primary: AppColors.accent, secondary: AppColors.accent, surface: AppColors.surface),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.merge(displayStyle),
        displayMedium: baseTextTheme.displayMedium?.merge(displayStyle),
        displaySmall: baseTextTheme.displaySmall?.merge(displayStyle),
        headlineLarge: baseTextTheme.headlineLarge?.merge(displayStyle),
        headlineMedium: baseTextTheme.headlineMedium?.merge(displayStyle),
        headlineSmall: baseTextTheme.headlineSmall?.merge(displayStyle),
        titleLarge: baseTextTheme.titleLarge?.merge(displayStyle),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.displayFamily,
          fontFamilyFallback: AppFonts.displayFallback,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.surfaceElevated,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide(color: AppColors.accent)),
      ),
    );
  }
}
