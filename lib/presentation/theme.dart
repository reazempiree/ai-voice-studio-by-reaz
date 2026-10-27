import 'package:flutter/material.dart';

const studioInk = Color(0xFF282824);
const studioGold = Color(0xFF92753E);
const studioPaper = Color(0xFFF7F5F0);

ThemeData studioTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: studioGold,
    brightness: Brightness.light,
    surface: studioPaper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'NotoSerifBengali',
    scaffoldBackgroundColor: studioPaper,
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'NotoSerifBengali',
      bodyColor: studioInk,
      displayColor: studioInk,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: studioPaper,
      foregroundColor: studioInk,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE8E3D8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDDD7CA)),
      ),
      contentPadding: const EdgeInsets.all(18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: studioInk,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFEFE7D6),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    dividerColor: const Color(0xFFE8E3D8),
  );
}
