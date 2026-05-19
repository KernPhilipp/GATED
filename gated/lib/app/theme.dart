import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _cardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
);

const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(18)),
);

ThemeData buildLightTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFCAF0F8),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );

  return base.copyWith(
    textTheme: GoogleFonts.barlowSemiCondensedTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.barlowSemiCondensedTextTheme(
      base.primaryTextTheme,
    ),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: _cardShape,
    ),
    filledButtonTheme: FilledButtonThemeData(style: _buildRoundedButtonStyle()),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buildRoundedButtonStyle(),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buildRoundedButtonStyle(),
    ),
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF03045E),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  return base.copyWith(
    textTheme: GoogleFonts.barlowSemiCondensedTextTheme(base.textTheme),
    primaryTextTheme: GoogleFonts.barlowSemiCondensedTextTheme(
      base.primaryTextTheme,
    ),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: _cardShape,
    ),
    filledButtonTheme: FilledButtonThemeData(style: _buildRoundedButtonStyle()),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buildRoundedButtonStyle(),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buildRoundedButtonStyle(),
    ),
  );
}

ButtonStyle _buildRoundedButtonStyle() {
  return ButtonStyle(
    shape: const WidgetStatePropertyAll(_buttonShape),
    shadowColor: const WidgetStatePropertyAll(Colors.black38),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return 0;
      }
      if (states.contains(WidgetState.pressed)) {
        return 1;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return 4;
      }
      return 0;
    }),
  );
}
