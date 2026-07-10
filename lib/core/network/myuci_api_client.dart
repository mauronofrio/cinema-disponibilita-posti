import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_error.dart';
import 'uci_dio_provider.dart';

/// Typed client for UCI's public content backend: theatre listing and daily
/// programming (films/showtimes). Read-only, same philosophy as
/// [TheSpaceApiClient] - see PROJECT_NOTES.md for the endpoints themselves.
class MyUciApiClient {
  MyUciApiClient(this._dio);

  final Dio _dio;

  Future<List<String>> getProgrammingDays(String theatreSlug) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/theatres/$theatreSlug/programmingDays',
      );
      return (response.data ?? const []).cast<String>();
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }

  Future<List<dynamic>> getProgramming(String theatreSlug, String date) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/theatres/$theatreSlug/programming/$date',
      );
      return response.data!['data'] as List<dynamic>? ?? const [];
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }
}

final myUciApiClientProvider = Provider<MyUciApiClient>((ref) {
  return MyUciApiClient(ref.watch(myUciDioProvider));
});
