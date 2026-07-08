import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_localizations.dart';
import 'update_checker.dart';

/// Shared by the automatic on-start prompt (see `_UpdateCheckGate` in
/// app.dart) and the persistent app-bar icon on the showtimes screen (see
/// `showtimes_home_screen.dart`) - dismissing the automatic prompt shouldn't
/// mean losing the only way back to it before the next app restart.
Future<void> showUpdateDialog(BuildContext context, AvailableUpdate update) async {
  final t = AppLocalizations.of(context);
  final download = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.updateAvailableTitle),
      content: Text(
        t.updateAvailableMessage(update.latestVersion, update.currentVersion),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.updateLater),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.updateDownload),
        ),
      ],
    ),
  );
  if (download == true) {
    await launchUrl(
      Uri.parse(update.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}
