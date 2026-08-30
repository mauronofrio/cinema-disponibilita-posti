import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/api_client.dart';
import 'chain_api.dart';

/// Thin [ChainApi] wrapper around [TheSpaceApiClient] - the client already
/// speaks the shared models directly, so there's no translation to do here
/// beyond unwrapping [Cinema]/[Session] to the bare ids it takes.
class TheSpaceChainApi implements ChainApi {
  TheSpaceChainApi(this._client);

  final TheSpaceApiClient _client;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) {
    // Same reasoning as getSeatMap below: _client.getShowingDates already
    // turns a network/HTTP failure into a friendly ApiException, but the
    // model mapping that runs after that (ShowingDate.fromJson's
    // `json['hasShowings'] as bool` hard cast, no default) is not - a
    // backend schema change there would otherwise surface as a raw Dart
    // type error in the UI instead of the same friendly message every
    // other chain gives.
    return runChainParsing(() => _client.getShowingDates(cinema.cinemaId));
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) {
    // The Space's own endpoint already returns every day in one cheap
    // response - [day] doesn't change what's fetched, only which of the
    // returned films end up shown (the caller filters that).
    //
    // Wrapped for the same reason as getShowingDates above: Film.fromJson's
    // `json['filmId'] as String` hard cast runs unprotected after
    // _client.getFilmsForCinema's own transport-error handling.
    return runChainParsing(() => _client.getFilmsForCinema(cinema.cinemaId));
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) {
    // _client.getSeatMapJson already turns a network/HTTP failure into a
    // friendly ApiException (see api_client.dart's _throwFriendly) - but
    // SeatMap.fromApiResponseJson's own unchecked JSON mapping runs after
    // that, inside compute() below, which is no more protected against a
    // malformed body than any other chain's parsing step. runChainParsing
    // covers that half specifically, without double-wrapping the part
    // api_client.dart already handles.
    return runChainParsing(() async {
      final raw = await _client.getSeatMapJson(
        cinema.cinemaId,
        session.sessionId,
      );
      // Both jsonDecode and the model mapping happen off the UI isolate: the
      // response can be several hundred KB, dominated by redundant per-seat
      // metadata that SeatMap.fromApiResponseJson also strips down to just
      // what the grid needs.
      return compute(SeatMap.fromApiResponseJson, raw);
    });
  }
}

final theSpaceChainApiProvider = Provider<TheSpaceChainApi>((ref) {
  return TheSpaceChainApi(ref.watch(apiClientProvider));
});
