import 'package:flutter/material.dart';

import '../core/sport.dart';

/// Die vier Designs aus der Web-App – Farben 1:1 aus css/app.css übernommen.
enum TriDesign {
  nacht('Nacht'),
  gletscher('Gletscher'),
  asphalt('Asphalt'),
  nordsee('Nordsee');

  const TriDesign(this.label);
  final String label;

  static TriDesign parse(Object? s) => TriDesign.values.firstWhere((d) => d.name == s, orElse: () => TriDesign.nacht);
}

@immutable
class TriColors extends ThemeExtension<TriColors> {
  const TriColors({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.swim,
    required this.bike,
    required this.run,
    required this.str,
    required this.oth,
    required this.fit,
    required this.fat,
    required this.form,
    required this.good,
    required this.warn,
    required this.bad,
    required this.radius,
    required this.tileRadius,
    required this.upperLabels,
  });

  final Color bg, bg2, surface, surface2, line, fg, muted, faint, accent, onAccent;
  final Color swim, bike, run, str, oth, fit, fat, form, good, warn, bad;
  final double radius, tileRadius;
  final bool upperLabels;

  Color sport(Sport? s) => switch (s) {
        Sport.swim => swim,
        Sport.bike => bike,
        Sport.run => run,
        Sport.strength => str,
        _ => oth,
      };

  static TriColors of(BuildContext context) => Theme.of(context).extension<TriColors>()!;

  static const nacht = TriColors(
    bg: Color(0xFF0B0D12), bg2: Color(0xFF0B0D12), surface: Color(0xFF151822), surface2: Color(0xFF1D2130), line: Color(0xFF272C3C),
    fg: Color(0xFFEEF0F6), muted: Color(0xFF8B91A4), faint: Color(0xFF5D6376), accent: Color(0xFFF24566), onAccent: Colors.white,
    swim: Color(0xFF33B8F2), bike: Color(0xFFFF9426), run: Color(0xFF4DD973), str: Color(0xFFC77DFF), oth: Color(0xFF2FD6C3),
    fit: Color(0xFF5A8CFF), fat: Color(0xFFF2598C), form: Color(0xFFFFCC33), good: Color(0xFF3CCF74), warn: Color(0xFFFFB020), bad: Color(0xFFFF5A5A),
    radius: 18, tileRadius: 18, upperLabels: false,
  );
  static const gletscher = TriColors(
    bg: Color(0xFFEEF2F6), bg2: Color(0xFFE4EAF1), surface: Color(0xFFFFFFFF), surface2: Color(0xFFEEF2F7), line: Color(0xFFDDE3EC),
    fg: Color(0xFF111827), muted: Color(0xFF5B6475), faint: Color(0xFF9AA3B2), accent: Color(0xFF2453FF), onAccent: Colors.white,
    swim: Color(0xFF0A8FD1), bike: Color(0xFFE36B00), run: Color(0xFF11A34A), str: Color(0xFF8B3FD9), oth: Color(0xFF0F9C8C),
    fit: Color(0xFF2453FF), fat: Color(0xFFD6336C), form: Color(0xFFC98A00), good: Color(0xFF11A34A), warn: Color(0xFFC98A00), bad: Color(0xFFE03131),
    radius: 22, tileRadius: 18, upperLabels: false,
  );
  static const asphalt = TriColors(
    bg: Color(0xFF18191C), bg2: Color(0xFF18191C), surface: Color(0xFF222327), surface2: Color(0xFF2B2C31), line: Color(0xFF34363C),
    fg: Color(0xFFF3F1EE), muted: Color(0xFF9A978F), faint: Color(0xFF66645E), accent: Color(0xFFFF6A13), onAccent: Colors.white,
    swim: Color(0xFF4CC3FF), bike: Color(0xFFFFB000), run: Color(0xFF9BE564), str: Color(0xFFD08CFF), oth: Color(0xFF5EE0CF),
    fit: Color(0xFF4CC3FF), fat: Color(0xFFFF6A13), form: Color(0xFFFFE14D), good: Color(0xFF3CCF74), warn: Color(0xFFFFB020), bad: Color(0xFFFF5A5A),
    radius: 6, tileRadius: 4, upperLabels: true,
  );
  static const nordsee = TriColors(
    bg: Color(0xFF06222B), bg2: Color(0xFF0A2F3A), surface: Color(0xFF0B3340), surface2: Color(0xFF11414F), line: Color(0xFF17505F),
    fg: Color(0xFFEAF6F7), muted: Color(0xFF8FB3BA), faint: Color(0xFF5A8590), accent: Color(0xFFFF7A59), onAccent: Colors.white,
    swim: Color(0xFF5FD4FF), bike: Color(0xFFFFC15E), run: Color(0xFF7EF0A8), str: Color(0xFFD9A3FF), oth: Color(0xFF4FF0D8),
    fit: Color(0xFF5FD4FF), fat: Color(0xFFFF7A59), form: Color(0xFFFFE08A), good: Color(0xFF3CCF74), warn: Color(0xFFFFB020), bad: Color(0xFFFF5A5A),
    radius: 24, tileRadius: 20, upperLabels: false,
  );

  static TriColors forDesign(TriDesign d) => switch (d) {
        TriDesign.nacht => nacht,
        TriDesign.gletscher => gletscher,
        TriDesign.asphalt => asphalt,
        TriDesign.nordsee => nordsee,
      };

  @override
  TriColors copyWith() => this;

  @override
  TriColors lerp(ThemeExtension<TriColors>? other, double t) => t < .5 || other is! TriColors ? this : other;
}

ThemeData buildTheme(TriDesign design) {
  final c = TriColors.forDesign(design);
  final dark = design != TriDesign.gletscher;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.surface,
    onSurface: c.fg,
    surfaceContainerHighest: c.surface2,
    outline: c.line,
    outlineVariant: c.line,
    error: c.bad,
  );
  final radius = BorderRadius.circular(c.radius);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    appBarTheme: AppBarTheme(backgroundColor: c.bg, foregroundColor: c.fg, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: design == TriDesign.gletscher ? 1 : 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: design == TriDesign.gletscher ? BorderSide.none : BorderSide(color: c.line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accent.withValues(alpha: .2),
      labelTextStyle: WidgetStateProperty.all(TextStyle(fontSize: 11, color: c.fg)),
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: c.surface, indicatorColor: c.accent.withValues(alpha: .2)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: c.surface2, contentTextStyle: TextStyle(color: c.fg)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, showDragHandle: true),
  );
}
