import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/seat_map.dart';

/// Design tokens for "The Space (non ufficiale)".
///
/// Direction: a dark auditorium rather than a light dashboard - the app is
/// used in the same low-light moments as the cinema itself. The palette
/// deliberately avoids The Space's own red/white branding (this is an
/// unofficial companion, not a skin of it) and instead pulls from the
/// *generic* vocabulary of going to the movies: marquee-bulb amber, the warm
/// off-white of a lit screen, and the muted tones of a dark room.
///
/// The one functional idea the whole palette is built around: since the
/// entire point of the seat map is "show me what's free", available seats
/// get the single saturated, glowing color in the whole app - everything
/// else (occupied, reserved, even the chrome around it) is deliberately
/// muted so the free seats are the only thing that pops.
class AppColors {
  const AppColors._();

  static const background = Color(0xFF15141A);
  static const surface = Color(0xFF201E26);
  static const surfaceElevated = Color(0xFF2A2733);
  static const hairline = Color(0x3A38354A);

  static const textPrimary = Color(0xFFF3EFE8);
  static const textMuted = Color(0xFF948FA0);

  /// Marquee-bulb amber: the only "brand" accent. Used for the selected day
  /// chip, active nav, and other things that mean "this one, right now".
  static const marquee = Color(0xFFE8A23A);

  /// Fallback fill for an available seat whose category has no color of its
  /// own; every non-available seat, regardless of category, shares this one
  /// muted grey (see seat_grid.dart) - it can't be picked, so its category
  /// no longer matters.
  static const seatAvailable = Color(0xFF45C7AE);
  static const seatOccupied = Color(0xFF322F3A);
}

String labelForSeatStatus(SeatStatus status) {
  switch (status) {
    case SeatStatus.available:
      return 'Disponibile';
    case SeatStatus.occupied:
      return 'Occupato';
    case SeatStatus.reserved:
      return 'Riservato';
    case SeatStatus.special:
      return 'Speciale';
    case SeatStatus.accessibility:
      return 'Accessibilità';
    case SeatStatus.unknown:
      return 'Non disponibile';
  }
}

/// Parses the API's `"#RRGGBB"` area color strings. Returns null for
/// anything else so callers can fall back to a neutral color.
Color? colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

class AppTheme {
  const AppTheme._();

  /// Condensed marquee-poster caps: film titles, screen headers, big day
  /// labels. Used with restraint - never for body copy.
  static TextStyle display(BuildContext context) => GoogleFonts.bebasNeue();

  /// Everyday reading text: addresses, descriptions, buttons.
  static TextStyle body(BuildContext context) => GoogleFonts.manrope();

  /// Ticket-stub monospace: session times, seat row/column labels, prices -
  /// anything that reads like it was printed on a stub.
  static TextStyle mono(BuildContext context) => GoogleFonts.jetBrainsMono();

  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final bodyTextTheme = GoogleFonts.manropeTextTheme(base.textTheme);
    final displayFamily = GoogleFonts.bebasNeue().fontFamily;

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: AppColors.surface,
        primary: AppColors.marquee,
        secondary: AppColors.seatAvailable,
        onSurface: AppColors.textPrimary,
        onPrimary: const Color(0xFF211500),
      ),
      textTheme: bodyTextTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            headlineLarge: bodyTextTheme.headlineLarge?.copyWith(
              fontFamily: displayFamily,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
              fontSize: 34,
            ),
            headlineMedium: bodyTextTheme.headlineMedium?.copyWith(
              fontFamily: displayFamily,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
              fontSize: 26,
            ),
            titleLarge: bodyTextTheme.titleLarge?.copyWith(
              fontFamily: displayFamily,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.4,
              fontSize: 22,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: displayFamily,
          fontSize: 24,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.marquee,
        labelStyle: bodyTextTheme.labelLarge?.copyWith(
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: bodyTextTheme.labelLarge?.copyWith(
          color: const Color(0xFF211500),
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}
