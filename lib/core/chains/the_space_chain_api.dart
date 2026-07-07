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
    return _client.getShowingDates(cinema.cinemaId);
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) {
    // The Space's own endpoint already returns every day in one cheap
    // response - [day] doesn't change what's fetched, only which of the
    // returned films end up shown (the caller filters that).
    return _client.getFilmsForCinema(cinema.cinemaId);
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async {
    final raw = await _client.getSeatMapJson(
      cinema.cinemaId,
      session.sessionId,
    );
    // Both jsonDecode and the model mapping happen off the UI isolate: the
    // response can be several hundred KB, dominated by redundant per-seat
    // metadata that SeatMap.fromApiResponseJson also strips down to just
    // what the grid needs.
    return compute(SeatMap.fromApiResponseJson, raw);
  }
}

final theSpaceChainApiProvider = Provider<TheSpaceChainApi>((ref) {
  return TheSpaceChainApi(ref.watch(apiClientProvider));
});
