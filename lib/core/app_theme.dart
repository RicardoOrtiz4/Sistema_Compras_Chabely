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
        style: _filledButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _elevatedButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _textButtonStyle(
          scheme: scheme,
          border: buttonBorder,
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
        style: _filledButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _elevatedButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _textButtonStyle(
          scheme: scheme,
          border: buttonBorder,
          shape: buttonShape,
        ),
      ),
    );
  }

  static ButtonStyle _filledButtonStyle({
    required ColorScheme scheme,
    required BorderSide border,
    required OutlinedBorder shape,
  }) {
    return FilledButton.styleFrom(
      side: border,
      shape: shape,
    ).copyWith(
      animationDuration: const Duration(milliseconds: 170),
      elevation: _elevation(0, 5, 2),
      shadowColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.26)),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.16);
        }
        if (states.contains(WidgetState.hovered)) {
          return Colors.white.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.08);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: scheme.primary.withValues(alpha: 0.72), width: 1.4);
        }
        return border;
      }),
    );
  }

  static ButtonStyle _outlinedButtonStyle({
    required ColorScheme scheme,
    required BorderSide border,
    required OutlinedBorder shape,
  }) {
    return OutlinedButton.styleFrom(
      side: border,
      shape: shape,
    ).copyWith(
      animationDuration: const Duration(milliseconds: 170),
      elevation: _elevation(0, 2, 1),
      shadowColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.16)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: 0.12);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: scheme.primary.withValues(alpha: 0.80), width: 1.4);
        }
        return border;
      }),
    );
  }

  static ButtonStyle _elevatedButtonStyle({
    required ColorScheme scheme,
    required BorderSide border,
    required OutlinedBorder shape,
  }) {
    return ElevatedButton.styleFrom(
      side: border,
      shape: shape,
      elevation: 0,
    ).copyWith(
      animationDuration: const Duration(milliseconds: 170),
      elevation: _elevation(0, 6, 3),
      shadowColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.22)),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.09);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: scheme.primary.withValues(alpha: 0.72), width: 1.4);
        }
        return border;
      }),
    );
  }

  static ButtonStyle _textButtonStyle({
    required ColorScheme scheme,
    required BorderSide border,
    required OutlinedBorder shape,
  }) {
    return TextButton.styleFrom(
      side: border,
      shape: shape,
    ).copyWith(
      animationDuration: const Duration(milliseconds: 170),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.08);
        }
        return null;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.04);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: scheme.primary.withValues(alpha: 0.60), width: 1.3);
        }
        return border;
      }),
    );
  }

  static WidgetStateProperty<double?> _elevation(
    double normal,
    double hovered,
    double pressed,
  ) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return pressed;
      if (states.contains(WidgetState.hovered)) return hovered;
      return normal;
    });
  }

  static Color _onColor(Color color) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }
}
