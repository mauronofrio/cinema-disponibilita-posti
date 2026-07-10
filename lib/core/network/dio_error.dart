import 'package:dio/dio.dart';

import '../localization/app_localizations.dart';
import 'api_client.dart' show ApiException;

/// Generic fallback for a failed request, shared by every chain client: no
/// response at all (DNS/connectivity/timeout) gets a plain-language
/// connection error, anything else falls back to a generic "request
/// failed" - chain-specific extras (unwrapping an API's own error message,
/// WebTic's logical-200-but-failed body check) stay in each client and call
/// this only once they've run out of their own, more specific options.
Never throwFriendlyDioError(DioException e) {
  if (e.response == null) {
    throw ApiException(AppLocalizations.current.connectionError);
  }
  throw ApiException(AppLocalizations.current.requestFailedError);
}
