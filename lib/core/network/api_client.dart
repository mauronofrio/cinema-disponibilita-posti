import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_provider.dart';
import '../models/film.dart';
import '../models/showing_date.dart';
import '../models/seat_map.dart';

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
      final status = e.response?.statusCode;
      if (status == 401 || status == 404) {
        // Cookie may have expired or never took; re-warm once and retry.
        await _warmUp();
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/microservice$path',
          queryParameters: query,
        );
        return response.data!;
      }
      rethrow;
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
    Future<Response<String>> request() => _dio.get<String>(
      '/api/microservice/booking/Session/$cinemaId/$sessionId/seats',
      options: Options(responseType: ResponseType.plain),
    );
    try {
      final response = await request();
      return response.data!;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 404) {
        await _warmUp();
        final response = await request();
        return response.data!;
      }
      rethrow;
    }
  }
}

final apiClientProvider = Provider<TheSpaceApiClient>((ref) {
  return TheSpaceApiClient(ref.watch(dioProvider));
});
