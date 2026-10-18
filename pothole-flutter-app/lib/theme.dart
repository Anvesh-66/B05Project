import 'package:flutter/material.dart';

import 'models/severity.dart';

export 'models/severity.dart';

/// The app's colours. Light and dark each have a full set, so screens read them
/// through `context.colors` and never hard-code one.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.primarySoftBorder,
    required this.background,
    required this.card,
    required this.surface,
    required this.text,
    required this.muted,
    required this.border,
    required this.high,
    required this.highSoft,
    required this.medium,
    required this.mediumSoft,
    required this.low,
    required this.lowSoft,
  });

  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color primarySoftBorder;
  final Color background;
  final Color card;
  final Color surface;
  final Color text;
  final Color muted;
  final Color border;
  final Color high;
  final Color highSoft;
  final Color medium;
  final Color mediumSoft;
  final Color low;
  final Color lowSoft;

  static const light = AppColors(
    primary: Color(0xFF016ED3),
    primaryDark: Color(0xFF0056B3),
    primarySoft: Color(0xFFE2F1FF),
    primarySoftBorder: Color(0xFFCFE8FF),
    background: Color(0xFFEEF3F8),
    card: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F9FC),
    text: Color(0xFF0A0A0A),
    muted: Color(0xFF64748B),
    border: Color(0xFFE3EAF2),
    high: Color(0xFFDC2626),
    highSoft: Color(0xFFFEE2E2),
    medium: Color(0xFFD97706),
    mediumSoft: Color(0xFFFEF3C7),
    low: Color(0xFF059669),
    lowSoft: Color(0xFFD1FAE5),
  );

  static const dark = AppColors(
    primary: Color(0xFF3B93E8),
    primaryDark: Color(0xFF016ED3),
    primarySoft: Color(0xFF0F2A47),
    primarySoftBorder: Color(0xFF163A61),
    background: Color(0xFF070C14),
    card: Color(0xFF111A27),
    surface: Color(0xFF0B1220),
    text: Color(0xFFE8EEF6),
    muted: Color(0xFF8A99AD),
    border: Color(0xFF1E2A3B),
    high: Color(0xFFF26B6B),
    highSoft: Color(0xFF3A1414),
    medium: Color(0xFFF0A63A),
    mediumSoft: Color(0xFF3A2A0C),
    low: Color(0xFF34C28F),
    lowSoft: Color(0xFF0C3326),
  );

  /// Text colour and tinted background for a severity level.
  ({Color color, Color soft}) of(Severity severity) => switch (severity) {
        Severity.high => (color: high, soft: highSoft),
        Severity.medium => (color: medium, soft: mediumSoft),
        Severity.low => (color: low, soft: lowSoft),
      };

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
}

const double cardRadius = 18;
const double controlRadius = 14;

/// Space around a screen's scrolling content. The bottom leaves room for the tab bar.
const EdgeInsets screenPadding = EdgeInsets.fromLTRB(18, 8, 18, 28);

ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = base.textTheme
      .apply(bodyColor: c.text, displayColor: c.text)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, color: c.text),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, color: c.text),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, color: c.muted),
        labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 11, color: c.muted, letterSpacing: 0.4),
      );
  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius));
  // Built from the theme's own label style so buttons keep the app's font.
  final buttonText = textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.surface,
    colorScheme: ColorScheme.fromSeed(seedColor: c.primary, brightness: brightness).copyWith(
      primary: c.primary,
      onPrimary: Colors.white,
      surface: c.card,
      onSurface: c.text,
      error: c.high,
      outline: c.border,
    ),
    textTheme: textTheme,
    extensions: [c],
    dividerColor: c.border,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: c.primary.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        minimumSize: const Size(0, 50),
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        backgroundColor: c.card,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: c.primarySoftBorder),
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        textStyle: buttonText?.copyWith(fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(color: c.muted, fontSize: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.primary, width: 1.5)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0B1220),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: controlShape,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.primarySoft),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.primary : c.border,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
