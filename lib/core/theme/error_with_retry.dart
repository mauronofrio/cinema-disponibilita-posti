import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import 'app_theme.dart';

/// An error message with an explicit way out of it.
///
/// Pull-to-refresh alone isn't enough as the only retry affordance: it's
/// invisible (nothing on screen says it exists), and on a short error
/// message there's barely anything to pull. Every failed load in this app
/// gets a real button instead.
class ErrorWithRetry extends StatelessWidget {
  const ErrorWithRetry({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: AppTheme.body(context).copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(t.retry),
          ),
        ],
      ),
    );
  }
}
