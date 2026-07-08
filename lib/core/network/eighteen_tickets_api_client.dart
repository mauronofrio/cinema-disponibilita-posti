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

/// Typed client for the "18tickets.net" platform - shared by every
/// independent cinema built on it (confirmed live: RedCarpet Cinema -
/// Monopoli and Multicinema Galleria - Bari are the same backend, just a
/// different venue each), which serves plain server-rendered HTML/SVG
/// rather than a JSON API (see PROJECT_NOTES.md). No auth of any kind on any
/// of these, confirmed live.
///
/// Every call takes the venue's own `host` (`Cinema.host`, e.g.
/// "monopoli.redcarpetcinema.it") rather than a fixed base URL: unlike
/// UCI/WebTic, this platform is one deployment per cinema, so there's no
/// single shared host to bake into the client.
class EighteenTicketsApiClient {
  EighteenTicketsApiClient(this._dio);

  final Dio _dio;

  Future<String> _getHtml(
    String url, {
    Map<String, dynamic>? query,
    bool xhr = false,
  }) async {
    try {
      final response = await _dio.get<String>(
        url,
        queryParameters: query,
        // The "fetch_*" fragment endpoints 406 without this - the server
        // checks `request.xhr?` to decide whether to render the jQuery
        // fragment at all, confirmed live (a plain GET with no headers on
        // fetch_film_occupations returns 406, adding this returns 200).
        options: Options(
          responseType: ResponseType.plain,
          headers: xhr ? {'X-Requested-With': 'XMLHttpRequest'} : null,
        ),
      );
      return response.data!;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  /// The cinema's homepage - only used for the list of days the day-picker
  /// offers (`data-target` on each `.select-date` balloon); its own static
  /// film list is never read, `fetch_films` (below) gives richer data anyway.
  Future<String> getHomepage(String host) => _getHtml('https://$host/');

  /// Every film showing on one specific day, *with that day's own
  /// showtimes already embedded* - one request covers every film for that
  /// day, no per-film request needed (see PROJECT_NOTES.md - this replaced
  /// an earlier "one request per film per day" design that got the app
  /// rate-limited on this small site once a cinema had ~20 films).
  Future<String> getFilmsForDay(String host, String date) {
    return _getHtml(
      'https://$host/film/fetch_films',
      query: {'date': date},
      xhr: true,
    );
  }

  /// One specific showtime's own page - the only place this platform
  /// exposes which room (`data-theater`) that showtime plays in; not worth
  /// fetching for every showtime up front, only called lazily when the user
  /// opens that one session's seat map (see
  /// `EighteenTicketsChainApi.getSeatMap`).
  Future<String> getFilmSessionPage(
    String host,
    String filmId,
    String sessionId,
  ) {
    return _getHtml('https://$host/film/$filmId/$sessionId');
  }

  /// Every real showtime a film has, on any date, in one request - an empty
  /// `date` is the same "+ Tutte le Date" (All Dates) selection its own
  /// date-balloon picker offers, confirmed live to return every one of a
  /// film's real showtimes across every day at once (e.g. two today, two
  /// tomorrow), unlike the film's bare overview page (`/film/{filmId}`,
  /// this call's own params omitted entirely), which only ever renders one
  /// narrower, undocumented default window and silently drops other real,
  /// bookable days. Only used for `Cinema.scheduleFromFilmPages` cinemas
  /// (see `EighteenTicketsChainApi`) as a fallback when `fetch_films` itself
  /// never renders any time slots for any day - a normal 18tickets venue
  /// never needs this, `fetch_films` already gives every day's showtimes in
  /// one request.
  Future<String> getAllFilmOccupations(String host, String filmId) {
    return _getHtml(
      'https://$host/film/$filmId/fetch_film_occupations',
      query: {'date': '', 'invite_code': ''},
      xhr: true,
    );
  }

  /// Seat-by-seat occupancy for one showtime. Returns JSON as text (small
  /// enough that decoding inline is fine, no need for the compute()
  /// treatment The Space's much larger seat responses need).
  Future<String> getSeatOccupancy(String host, String performanceId) {
    return _getHtml(
      'https://$host/seats/$performanceId',
      query: {'caller_id': 0, 'invite_code': ''},
    );
  }

  /// The room's physical seat layout, as SVG - shared across every showtime
  /// in that room, keyed by `theaterId` (from `data-theater` on a showtime),
  /// not by performance.
  Future<String> getTheaterSvg(String host, String theaterId) {
    return _getHtml('https://$host/theater/$theaterId.svg');
  }
}

final eighteenTicketsApiClientProvider = Provider<EighteenTicketsApiClient>((
  ref,
) {
  return EighteenTicketsApiClient(Dio());
});
