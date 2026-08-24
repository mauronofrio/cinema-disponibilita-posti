import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_error.dart';

const _tmdbBaseUrl = 'https://api.themoviedb.org/3';

/// Read with `--dart-define=TMDB_READ_ACCESS_TOKEN=...` at build/run time -
/// never committed. Empty when the app was built without it; callers (see
/// film_info_provider.dart) check for that *before* ever constructing this
/// client, so an empty token here never actually reaches a real request.
const tmdbReadAccessToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');

/// Typed client for TMDb's read-only search/videos endpoints. Same
/// "client returns raw JSON text, a separate pure function parses it" split
/// as every other chain client (see tmdb_film_info_parser.dart).
class TmdbApiClient {
  TmdbApiClient(this._dio);

  final Dio _dio;

  Future<String> searchMovie(String title, String language) async {
    try {
      final response = await _dio.get<String>(
        '/search/movie',
        queryParameters: {'query': title, 'language': language},
        options: Options(responseType: ResponseType.plain),
      );
      return response.data!;
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }

  Future<String> getVideos(int tmdbId, String language) async {
    try {
      final response = await _dio.get<String>(
        '/movie/$tmdbId/videos',
        queryParameters: {'language': language},
        options: Options(responseType: ResponseType.plain),
      );
      return response.data!;
    } on DioException catch (e) {
      throwFriendlyDioError(e);
    }
  }
}

final tmdbApiClientProvider = Provider<TmdbApiClient>((ref) {
  return TmdbApiClient(
    Dio(
      BaseOptions(
        baseUrl: _tmdbBaseUrl,
        headers: {'Authorization': 'Bearer $tmdbReadAccessToken'},
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    ),
  );
});
