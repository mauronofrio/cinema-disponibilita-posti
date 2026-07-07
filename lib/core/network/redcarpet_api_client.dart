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

/// Typed client for RedCarpet Cinema's own booking site - a small,
/// independent cinema (not a chain) built on the "18tickets.net" platform,
/// which serves plain server-rendered HTML/SVG rather than a JSON API (see
/// PROJECT_NOTES.md). No auth of any kind on any of these, confirmed live.
///
/// Every call takes the venue's own `host` (`Cinema.host`, e.g.
/// "monopoli.redcarpetcinema.it") rather than a fixed base URL: unlike
/// UCI/WebTic, this platform is one deployment per cinema, so there's no
/// single shared host to bake into the client.
class RedCarpetApiClient {
  RedCarpetApiClient(this._dio);

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

  /// The cinema's homepage: embeds the full current playbill (one
  /// `.movie--preview` block per film, with title/poster/director/cast) and
  /// the list of days the day-picker offers (`data-target` on each
  /// `.select-date` balloon) - but NOT showtimes themselves, those are
  /// fetched separately per film per day.
  Future<String> getHomepage(String host) => _getHtml('https://$host/');

  /// One film's showtimes on one specific day - there's no bulk "every day
  /// at once" endpoint here either (same situation as UCI).
  Future<String> getFilmOccupations(String host, String filmId, String date) {
    return _getHtml(
      'https://$host/film/$filmId/fetch_film_occupations',
      query: {'date': date},
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

final redCarpetApiClientProvider = Provider<RedCarpetApiClient>((ref) {
  return RedCarpetApiClient(Dio());
});
