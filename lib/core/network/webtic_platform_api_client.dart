import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import 'api_client.dart' show ApiException;

Never _throwFriendly(DioException e) {
  if (e.response == null) {
    throw ApiException(AppLocalizations.current.connectionError);
  }
  throw ApiException(AppLocalizations.current.requestFailedError);
}

/// Client for the generic "Webtic" ticketing platform, as called *directly*
/// by a chain's own front-end site (confirmed live for Notorious Cinemas'
/// classic `cvu/modules` front end - see PROJECT_NOTES.md). Distinct from
/// `webtic_api_client.dart`, which talks to UCI's own English-translating
/// Cloud Run proxy in front of the same underlying backend, not this raw
/// surface - the two are not interchangeable even though both ultimately
/// reach the same `secure.webtic.it` infrastructure.
class WebticPlatformApiClient {
  WebticPlatformApiClient(this._dio);

  final Dio _dio;

  Future<String> _get(String url, Map<String, dynamic> query) async {
    try {
      final response = await _dio.get<String>(
        url,
        queryParameters: query,
        // Confirmed live: without this, the site sometimes answers with
        // HTTP 200 and a completely empty body instead of a clear error -
        // same underlying "request.xhr?" server-side check as the
        // 18tickets platform's fetch_* endpoints, just failing silently
        // here instead of with a proper 406.
        options: Options(
          responseType: ResponseType.plain,
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        ),
      );
      final body = response.data!;
      // Still seen occasionally even with the header above (probably
      // transient server-side rate limiting) - a bare empty body would
      // otherwise reach `json.decode` as a confusing FormatException.
      if (body.isEmpty) {
        throw ApiException(AppLocalizations.current.requestFailedError);
      }
      return body;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  /// One cinema's *entire* catalog - every film, every day, every showtime -
  /// in a single request (confirmed live: unlike 18tickets, there's no
  /// per-day or per-film cost here at all). [localId] is
  /// `Cinema.webticLocalId`; [host] is the chain's own front-end site (e.g.
  /// "www.notoriouscinemas.it"), shared by every venue of that chain.
  Future<String> getFullSchedule(String host, int localId) {
    return _get('https://$host/cvu/modules/prenoRapido.php', {
      'sel': 'getFullSched',
      'idcine': localId,
      'rand': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<String> _postWtService(String wtid, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post<String>(
        'https://secure.webtic.it/api/wtjsonservices.ashx',
        queryParameters: {'wtid': wtid},
        data: {'data': data},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      return response.data!;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  /// The room's physical seat layout - confirmed live to need no auth at
  /// all, unlike the reCAPTCHA-gated `getTicketsInfo` booking-flow call this
  /// app never needs to make (it only ever shows availability, never buys).
  Future<String> getMapSeats(int localId, int screenId) {
    return _postWtService('getMapSeats', {
      'LanguageId': 'it',
      'TrackId': '1',
      'LocalId': '$localId',
      'ScreenId': '$screenId',
      // Every showtime confirmed live so far uses "1" (standard 2D) here -
      // no 3D showing has turned up yet to confirm what a real 3D value
      // looks like (see PROJECT_NOTES.md).
      'ScreenModeId': '1',
    });
  }

  /// Which of that room's seats aren't free for one specific showtime.
  Future<String> getOccupancy(int localId, String performanceId) {
    return _postWtService('getOccupancy', {
      'LanguageId': 'it',
      'TrackId': '1',
      'LocalId': '$localId',
      'PerformanceId': performanceId,
    });
  }
}

final webticPlatformApiClientProvider = Provider<WebticPlatformApiClient>((
  ref,
) {
  return WebticPlatformApiClient(Dio());
});
