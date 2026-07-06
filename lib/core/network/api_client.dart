import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';
import '../models/film.dart';
import '../models/showing_date.dart';
import '../models/seat_map.dart';

/// A failure the API itself reported (HTTP error status, but with a JSON
/// body carrying a human-readable `errorMessage` - the backend does this
/// even for perfectly ordinary situations, e.g. a specific session's seat
/// data being temporarily unavailable). [message] is already fit to show
/// directly in the UI.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _htmlNamedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'hellip': '…',
  'agrave': 'à',
  'egrave': 'è',
  'igrave': 'ì',
  'ograve': 'ò',
  'ugrave': 'ù',
  'aacute': 'á',
  'eacute': 'é',
  'iacute': 'í',
  'oacute': 'ó',
  'uacute': 'ú',
};

/// Decodes the small set of HTML entities the API's error messages actually
/// use (Italian accented vowels, punctuation) - not a general HTML decoder,
/// just enough for text meant for a web page to read cleanly in a plain
/// Flutter `Text` widget.
String _decodeHtmlEntities(String input) {
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1)!;
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final code = int.tryParse(entity.substring(2), radix: 16);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    if (entity.startsWith('#')) {
      final code = int.tryParse(entity.substring(1));
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    return _htmlNamedEntities[entity] ?? match.group(0)!;
  });
}

/// Typed client for the public `thespacecinema.it` showings/booking API.
///
/// Deliberately calls only the read-only "showings" and seat-map endpoints.
/// It never touches order/payment/concessions endpoints - the official
/// app/website kick those off as soon as you tap a showtime even though all
/// you asked for was to see the seat map, which is the real cause of the
/// "seat map takes forever" complaint. Fetching the seats endpoint directly
/// (confirmed live to respond quickly on its own) avoids that entirely.
class TheSpaceApiClient {
  TheSpaceApiClient(this._dio);

  final Dio _dio;
  bool _warmedUp = false;

  Future<void> _warmUp() async {
    await _dio.get<void>('/');
    _warmedUp = true;
  }

  /// The API returns a JSON body with an `errorMessage` field even on error
  /// responses (4xx/5xx) - e.g. `{"responseCode":339,"errorMessage":"..."}`
  /// for a session whose seat data isn't available. That message is worth
  /// showing as-is; retrying the same request never fixes it, so this
  /// throws immediately instead of the previous retry-then-give-up dance,
  /// which just made a real error look like it was hanging.
  Never _throwFriendly(DioException e) {
    final data = e.response?.data;
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = json.decode(data);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is Map && decoded['errorMessage'] is String) {
      final raw = decoded['errorMessage'] as String;
      // Strip the API's HTML markup (<p>, <strong>, etc.) and decode its
      // entities (it sends "c'&egrave; stato" literally) - it's meant for
      // the official website, not a plain-text mobile UI.
      final plain = _decodeHtmlEntities(
        raw.replaceAll(RegExp('<[^>]*>'), ' '),
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (plain.isNotEmpty) throw ApiException(plain);
    }
    throw const ApiException(
      'Impossibile completare la richiesta. Riprova più tardi.',
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (!_warmedUp) {
      await _warmUp();
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/microservice$path',
        queryParameters: query,
      );
      return response.data!;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  Future<List<ShowingDate>> getShowingDates(String cinemaId) async {
    final json = await _getJson(
      '/showings/showingDates',
      query: {'cinemaId': cinemaId},
    );
    final result = json['result'] as List<dynamic>? ?? const [];
    return result
        .map((e) => ShowingDate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Film>> getFilmsForCinema(String cinemaId) async {
    final json = await _getJson('/showings/cinemas/$cinemaId/films');
    final result = json['result'] as List<dynamic>? ?? const [];
    return result.map((e) => Film.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns the raw JSON *text* for a session's seat map, deliberately left
  /// as a string (not decoded here via `dio`'s default JSON transformer) so
  /// callers can `jsonDecode` and map it to [SeatMap] together inside a
  /// single `compute()` call. The response can be several hundred KB and
  /// doing that work on the UI isolate is a real source of jank.
  Future<String> getSeatMapJson(String cinemaId, String sessionId) async {
    if (!_warmedUp) {
      await _warmUp();
    }
    try {
      final response = await _dio.get<String>(
        '/api/microservice/booking/Session/$cinemaId/$sessionId/seats',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data!;
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }
}

final apiClientProvider = Provider<TheSpaceApiClient>((ref) {
  return TheSpaceApiClient(ref.watch(dioProvider));
});
