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
      // One centred row; on a screen too narrow for all three the buttons
      // wrap onto a second centred line (the dialog's own overflow would
      // stack each one on its own line instead).
      actions: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
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
              FilledButton(
                onPressed: () => Navigator.pop(context, update.downloadUrl),
                child: Text(t.updateDownload),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  if (url != null) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
