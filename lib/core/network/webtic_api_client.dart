import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import 'api_client.dart' show ApiException;
import 'uci_dio_provider.dart';

Never _throwFriendly(DioException e) {
  if (e.response == null) {
    throw ApiException(AppLocalizations.current.connectionError);
  }
  throw ApiException(AppLocalizations.current.requestFailedError);
}

/// WebTic reports its own logical failures (bad id, expired performance...)
/// as a normal HTTP 200 with `Status.Success: false` in the body, not as an
/// HTTP error status - so those never reach a `DioException` at all. Worth
/// checking for on every call rather than only trusting the transport layer.
String _checkedBody(String raw) {
  final decoded = json.decode(raw);
  final status = decoded is Map ? decoded['Status'] : null;
  if (status is Map && status['Success'] == false) {
    final message = (status['Message'] as String?)?.trim();
    throw ApiException(
      message?.isNotEmpty == true
          ? message!
          : AppLocalizations.current.requestFailedError,
    );
  }
  return raw;
}

/// Typed client for the WebTic Api2 proxy UCI's seat map sits on. Returns
/// raw JSON *text*, not decoded here, so callers can decode and map to
/// [SeatMap] together inside a single `compute()` call - same reasoning as
/// [TheSpaceApiClient.getSeatMapJson].
class WebTicApiClient {
  WebTicApiClient(this._dio);

  final Dio _dio;

  Future<String> _post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post<String>(
        path,
        data: data,
        options: Options(responseType: ResponseType.plain),
      );
      return _checkedBody(response.data!);
    } on DioException catch (e) {
      _throwFriendly(e);
    }
  }

  Future<String> getScreen(int localId, int screenId) {
    return _post('/Screen', {'LocalId': localId, 'ScreenId': screenId});
  }

  Future<String> getOccupancy(int localId, String performanceId) {
    return _post('/Occupancy', {
      'LocalId': localId,
      'PerformanceId': performanceId,
    });
  }
}

final webTicApiClientProvider = Provider<WebTicApiClient>((ref) {
  return WebTicApiClient(ref.watch(webTicDioProvider));
});
