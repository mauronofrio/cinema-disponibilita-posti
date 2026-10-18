import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_localizations.dart';
import 'update_checker.dart';

/// Shared by the automatic on-start prompt (see `_UpdateCheckGate` in
/// app.dart) and the persistent app-bar icon on the showtimes screen (see
/// `showtimes_home_screen.dart`) - dismissing the automatic prompt shouldn't
/// mean losing the only way back to it before the next app restart.
Future<void> showUpdateDialog(
  BuildContext context,
  AvailableUpdate update,
) async {
  final t = AppLocalizations.of(context);
  final url = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.updateAvailableTitle),
      content: Text(
        t.updateAvailableMessage(update.latestVersion, update.currentVersion),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.updateLater),
        ),
        // The release page on GitHub, where its notes list what changed.
        TextButton(
          onPressed: () => Navigator.pop(context, update.notesUrl),
          child: Text(t.updateWhatsNew),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, update.downloadUrl),
          child: Text(t.updateDownload),
        ),
      ],
    ),
  );
  if (url != null) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
