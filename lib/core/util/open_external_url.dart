import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_localizations.dart';

/// Opens [url] in an external app/browser, telling the user when it can't
/// be opened instead of failing silently.
///
/// Every hand-off out of this app goes through here. `launchUrl` throws a
/// `PlatformException` when nothing on the device can handle the URL (no
/// browser at all, a restricted work profile, YouTube not installed and no
/// browser either) - and every call site used to fire it without awaiting,
/// so that exception only ever reached the logs: the user tapped "Compra i
/// biglietti" or "Guarda il trailer" and simply nothing happened, with no
/// way to tell a broken link from a slow one.
Future<void> openExternalUrl(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = AppLocalizations.of(context).linkOpenError;
  try {
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    // `launchUrl` also reports failure by returning false on some
    // platforms rather than throwing, so both paths need handling.
    if (!launched) messenger.showSnackBar(SnackBar(content: Text(message)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
