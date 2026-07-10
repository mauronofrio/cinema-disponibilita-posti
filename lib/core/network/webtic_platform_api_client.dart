import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import 'api_client.dart' show ApiException;
import 'dio_error.dart';

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
      throwFriendlyDioError(e);
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

  /// [WebticCatalogSource.programmingPage] chains only (Giometti Cinema so
  /// far): the one page listing every film currently showing at this venue,
  /// each with its own single day's showtimes (see the enum value's own doc
  /// for why that's a real platform limit, not a parsing shortcut). [slug]
  /// is `Cinema.slug`, the venue's own URL path segment.
  Future<String> getProgrammingPage(String host, String slug) {
    return _get('https://$host/cinema/$slug/programmazione', const {});
  }

  /// [WebticCatalogSource.filmSchedulePages] chains only (Cineplexx so far):
  /// the chain's own homepage, embedding the full film catalog plus, per
  /// film, which cinemas show it and on which days - see
  /// `parseWebticFilmCatalog`.
  Future<String> getFilmCatalogHomepage(String host) {
    return _get('https://$host/', const {});
  }

  /// [WebticCatalogSource.filmSchedulePages] chains only: one film's full
  /// week of showtimes at one specific cinema. [siteCinemaId] is
  /// `Cinema.slug` here (the venue's own site-internal numeric id, distinct
  /// from `Cinema.webticLocalId` - see `parseWebticFilmSchedulePage`).
  Future<String> getFilmSchedulePage(
    String host,
    String filmSlug,
    String filmId,
    String siteCinemaId,
  ) {
    return _get('https://$host/scheda/$filmSlug/$filmId/$siteCinemaId/', const {});
  }

  /// [WebticCatalogSource.fullSchedulePortal] chains only: the same catalog
  /// data as [getFullSchedule] (confirmed live to parse with the exact same
  /// `parseWebticFullSchedule`/`parseWebticShowingDays` - same
  /// `DS.Scheduling.Events[]` response shape), just fetched through the
  /// `www.webtic.it` Angular SPA's own backend instead of the chain's own
  /// front-end site - needed because these venues' front-ends don't expose
  /// `cvu/modules/prenoRapido.php` at all.
  Future<String> getFullScheduleViaPortal(int localId) async {
    try {
      final response = await _dio.post<String>(
        'https://restapi.webtic.it/Webtic/CallOldWebtic',
        data: {
          'OldWebticRequest': {
            'meta': {
              'QueryParams': {
                'wtid': 'getFullScheduling',
                'localid': localId,
                'trackid': 33,
              },
            },
          },
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final body = response.data!;
      if (body.isEmpty) {
        throw ApiException(AppLocalizations.current.requestFailedError);
      }
      return body;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  /// [WebticCatalogSource.madisonProgrammingPage] chains only ("Madison
  /// Cinemas"): the one page listing every film currently showing at this
  /// venue - unlike [getProgrammingPage], [slug] here is already the full
  /// page slug (`Cinema.slug`, e.g. "programmazione-cinema-madison-roma"),
  /// not a path segment under a shared `/cinema/.../programmazione`
  /// template.
  Future<String> getMadisonProgrammingPage(String host, String slug) {
    return _get('https://$host/$slug/', const {});
  }

  /// [WebticCatalogSource.madisonProgrammingPage] chains only: one film's
  /// real schedule at one cinema - confirmed live to cover a full week or
  /// more (unlike [getMadisonProgrammingPage] itself, which only ever
  /// server-renders today). [cinemaLocalId] is `Cinema.webticLocalId`,
  /// [filmId] is `ParsedMadisonCatalogFilm.filmId`.
  Future<String> getMadisonFilmDays(
    String host,
    int cinemaLocalId,
    String filmId,
  ) async {
    try {
      final response = await _dio.post<String>(
        'https://$host/wp-admin/admin-ajax.php',
        data: {
          'action': 'giorno_by_film_cinema',
          'cinema': cinemaLocalId,
          'film': filmId,
        },
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final body = response.data!;
      if (body.isEmpty) {
        throw ApiException(AppLocalizations.current.requestFailedError);
      }
      return body;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
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
      throwFriendlyDioError(e);
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
  return WebticPlatformApiClient(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );
});
