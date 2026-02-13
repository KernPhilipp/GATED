import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  );
}
