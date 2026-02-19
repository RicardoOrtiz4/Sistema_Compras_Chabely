import 'package:flutter/material.dart';

import 'package:sistema_compras/core/company_branding.dart';

class AppTheme {
  static ThemeData lightFor(CompanyBranding branding) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: branding.seedColor,
      brightness: Brightness.light,
    );
    var scheme = baseScheme.copyWith(
      surface: branding.lightSurface,
      surfaceContainerHighest: branding.lightSurfaceVariant,
    );
    final primary = branding.primaryColor ?? scheme.primary;
    final secondary = branding.secondaryColor ?? scheme.secondary;
    final tertiary = branding.tertiaryColor ?? scheme.tertiary;
    final secondaryContainer =
        branding.secondaryContainerColor ?? scheme.secondaryContainer;
    final tertiaryContainer = branding.tertiaryContainerColor ?? scheme.tertiaryContainer;
    scheme = scheme.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      secondary: secondary,
      onSecondary: _onColor(secondary),
      tertiary: tertiary,
      onTertiary: _onColor(tertiary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _onColor(secondaryContainer),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _onColor(tertiaryContainer),
    );
    final buttonBorder = BorderSide(color: scheme.primary, width: 1.2);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: branding.lightBackground,
      canvasColor: branding.lightBackground,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      dialogTheme: DialogThemeData(backgroundColor: branding.lightSurface),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
    );
  }

  static ThemeData darkFor(CompanyBranding branding) {
    var scheme = ColorScheme.fromSeed(
      seedColor: branding.seedColor,
      brightness: Brightness.dark,
    );
    final primary = branding.primaryColor ?? scheme.primary;
    final secondary = branding.secondaryColor ?? scheme.secondary;
    final tertiary = branding.tertiaryColor ?? scheme.tertiary;
    final secondaryContainer =
        branding.secondaryContainerColor ?? scheme.secondaryContainer;
    final tertiaryContainer = branding.tertiaryContainerColor ?? scheme.tertiaryContainer;
    scheme = scheme.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      secondary: secondary,
      onSecondary: _onColor(secondary),
      tertiary: tertiary,
      onTertiary: _onColor(tertiary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _onColor(secondaryContainer),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: _onColor(tertiaryContainer),
    );
    final buttonBorder = BorderSide(color: scheme.primary, width: 1.2);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          side: buttonBorder,
          shape: buttonShape,
        ),
      ),
    );
  }

  static Color _onColor(Color color) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }
}
