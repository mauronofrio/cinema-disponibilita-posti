import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_error.dart';

const twoTicketsBaseUrl = 'https://www.2tickets.it/biglietto';

/// Raw GETs against 2Tickets.it - see PROJECT_NOTES.md. Read-only by
/// design: the platform holds seats only via POST `/api/sala/addposto`
/// (a click on its own map), and nothing here ever POSTs.
class TwoTicketsApiClient {
  TwoTicketsApiClient(this._dio);

  final Dio _dio;

  Future<String> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final response = await _dio.get<String>(
        '$twoTicketsBaseUrl$path',
        queryParameters: query,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }

  Future<String> getVenuePage(String venueId) =>
      _get('/esercizio/titoli/$venueId');

  Future<String> getCheckoutPage(String filmId, String venueId) =>
      _get('/Acquisto/Checkout/$filmId/$venueId', {'settore': 'C'});

  Future<String> getSectors({
    required String eventId,
    required String time,
    required String serverEse,
    required String portEse,
  }) => _get('/api/sala/settori', {
    'idEvento': eventId,
    'tipo': 'C',
    'orarioTurno': time,
    'serverEse': serverEse,
    'portEse': portEse,
  });

  Future<String> getSeats({
    required int sectorId,
    required String eventId,
    required String rawTime,
    required String serverEse,
    required String portEse,
  }) => _get('/api/sala/posti', {
    'idSettore': sectorId,
    'modVend': 2,
    'idEvento': eventId,
    'orarioTurno': rawTime,
    'token': '',
    'clienteId': 0,
    'serverEse': serverEse,
    'portEse': portEse,
    'titoloEvento': '',
    'dataOraEvento': '',
  });
}

final twoTicketsApiClientProvider = Provider<TwoTicketsApiClient>((ref) {
  return TwoTicketsApiClient(
    Dio(
      BaseOptions(
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );
});
