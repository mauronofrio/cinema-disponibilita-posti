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
      // Three buttons don't fit on one row on a phone, and the dialog's
      // default overflow stacks them in a column: two secondary ones on top,
      // the download centred below instead.
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t.updateLater),
                ),
                // The release page on GitHub, where its notes list what changed.
                TextButton(
                  onPressed: () => Navigator.pop(context, update.notesUrl),
                  child: Text(t.updateWhatsNew),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, update.downloadUrl),
              child: Text(t.updateDownload),
            ),
          ],
        ),
      ],
    ),
  );
  if (url != null) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
