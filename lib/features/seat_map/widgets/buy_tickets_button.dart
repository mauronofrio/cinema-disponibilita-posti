import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/models/film.dart';
import '../../../core/theme/app_theme.dart';

/// Hands off to the official site's own booking flow for this exact
/// session - this app is a read-only viewer and never implements
/// booking/payment itself.
class BuyTicketsButton extends StatelessWidget {
  const BuyTicketsButton({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final bookingUrl = session.bookingPath;
    if (bookingUrl == null || bookingUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.marquee,
          foregroundColor: const Color(0xFF211500),
        ),
        onPressed: () => launchUrl(
          Uri.parse(bookingUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Text(
          AppLocalizations.of(context).buyTickets,
          style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
