import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// Shared workspace styling, based on the projects home screen.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.spaceMonoTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppPalette.text, displayColor: AppPalette.text);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppPalette.border),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.border),
    );
    final button = OutlinedButton.styleFrom(
      foregroundColor: AppPalette.text,
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: text.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppPalette.border),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppPalette.bg,
      canvasColor: AppPalette.bg,
      textTheme: text,
      primaryTextTheme: text,
      colorScheme: const ColorScheme.dark(
        primary: AppPalette.primary,
        onPrimary: AppPalette.bg,
        primaryContainer: AppPalette.surfaceAlt,
        onPrimaryContainer: AppPalette.text,
        secondary: AppPalette.text,
        onSecondary: AppPalette.bg,
        secondaryContainer: AppPalette.surfaceAlt,
        onSecondaryContainer: AppPalette.text,
        tertiary: AppPalette.muted,
        surface: AppPalette.surface,
        onSurface: AppPalette.text,
        onSurfaceVariant: AppPalette.muted,
        surfaceContainerHighest: AppPalette.surfaceAlt,
        outline: AppPalette.border,
        outlineVariant: AppPalette.border,
        error: AppPalette.error,
        surfaceTint: Colors.transparent,
      ),
      dividerColor: AppPalette.border,
      iconTheme: const IconThemeData(color: AppPalette.text, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.bg,
        foregroundColor: AppPalette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        shape: const Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceAlt,
        hintStyle: text.bodyMedium?.copyWith(color: AppPalette.muted),
        labelStyle: text.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.text),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: button.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppPalette.primary),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled)
                    ? AppPalette.muted
                    : AppPalette.bg,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: button.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppPalette.surfaceAlt),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.text,
          textStyle: text.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppPalette.surface,
        shape: shape,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: AppPalette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppPalette.surface,
        shape: shape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppPalette.bg,
        indicatorColor: AppPalette.surfaceAlt,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppPalette.text,
        unselectedLabelColor: AppPalette.muted,
        indicatorColor: AppPalette.text,
        dividerColor: AppPalette.border,
        labelStyle: text.labelLarge,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.surfaceAlt,
        foregroundColor: AppPalette.text,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppPalette.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppPalette.surfaceAlt,
        contentTextStyle: text.bodyMedium,
        actionTextColor: AppPalette.primary,
        behavior: SnackBarBehavior.floating,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppPalette.text,
        selectionColor: AppPalette.text.withValues(alpha: 0.2),
        selectionHandleColor: AppPalette.text,
      ),
    );
  }
}
