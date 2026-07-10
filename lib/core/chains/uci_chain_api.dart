import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/api_client.dart' show ApiException;
import '../network/myuci_api_client.dart';
import '../network/webtic_api_client.dart';
import 'chain_api.dart';
import 'uci/uci_film_parser.dart';
import 'uci/uci_seat_map_parser.dart';

/// [ChainApi] for UCI Cinemas. Two independent public backends are involved
/// (see PROJECT_NOTES.md): [MyUciApiClient] for programme content and
/// [WebTicApiClient] for the seat map, joined by `cinema.webticLocalId` and
/// `session.webticScreenId` - both come from the very same programming
/// response ([UciChainApi.getFilmsForCinema] embeds them into each
/// [Session] it builds).
class UciChainApi implements ChainApi {
  UciChainApi(this._myUci, this._webTic);

  final MyUciApiClient _myUci;
  final WebTicApiClient _webTic;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) {
    return runChainParsing(() async {
      final days = await _myUci.getProgrammingDays(cinema.cinemaId);
      return days
          .map((d) => ShowingDate(date: DateTime.parse(d), hasShowings: true))
          .toList();
    });
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) {
    return runChainParsing(() async {
      // [day] is unused - UCI has no per-day-cheap endpoint, so every
      // published day is fetched and merged regardless of which one the
      // caller actually wants shown right now (same one-time cost either way).
      final days = await _myUci.getProgrammingDays(cinema.cinemaId);
      // UCI has no single "every day at once" endpoint the way The Space
      // does, so every published day is fetched concurrently instead of one
      // at a time - this is the one-time cost of building the same "switch
      // day for free" UX the seat map screen offers for both chains.
      final perDay = await Future.wait(
        days.map((day) async {
          final json = await _myUci.getProgramming(cinema.cinemaId, day);
          return parseUciProgrammingDay(json, DateTime.parse(day));
        }),
      );

      final byFilmId = <String, List<ParsedUciDay>>{};
      for (final dayEntries in perDay) {
        for (final entry in dayEntries) {
          byFilmId.putIfAbsent(entry.filmId, () => []).add(entry);
        }
      }

      final films = byFilmId.values.map((entries) {
        final first = entries.first;
        final showingGroups =
            entries
                .map((d) => ShowingGroup(date: d.date, sessions: d.sessions))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        return Film(
          filmId: first.filmId,
          title: first.title,
          posterImageSrc: first.posterImageSrc,
          runningTime: first.runningTime,
          showingGroups: showingGroups,
        );
      }).toList();
      films.sort((a, b) => a.title.compareTo(b.title));
      return films;
    });
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) {
    return runChainParsing(() async {
      final localId = cinema.webticLocalId;
      final screenId = session.webticScreenId;
      if (localId == null || screenId == null) {
        throw ApiException(AppLocalizations.current.seatsLoadError);
      }
      final results = await Future.wait([
        _webTic.getScreen(localId, screenId),
        _webTic.getOccupancy(localId, session.sessionId),
      ]);
      return compute(
        parseUciSeatMap,
        UciSeatMapPayload(
          screenResponseBody: results[0],
          occupancyResponseBody: results[1],
        ),
      );
    });
  }
}

final uciChainApiProvider = Provider<UciChainApi>((ref) {
  return UciChainApi(
    ref.watch(myUciApiClientProvider),
    ref.watch(webTicApiClientProvider),
  );
});
