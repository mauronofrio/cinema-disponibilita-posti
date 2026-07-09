import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_localizations.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/api_client.dart' show ApiException;
import '../network/webtic_platform_api_client.dart';
import 'chain_api.dart';
import 'webtic/webtic_film_parser.dart';
import 'webtic/webtic_seat_map_parser.dart';

/// [ChainApi] for [CinemaChain.webtic] - chains whose own front-end site
/// calls the Webtic platform's classic `cvu/modules/prenoRapido.php`
/// endpoints directly (confirmed live for Notorious Cinemas). One
/// [getFullSchedule] call already returns a cinema's entire catalog - every
/// film, day and showtime at once - so both [getShowingDates] and
/// [getFilmsForDay] just fetch it fresh each time rather than caching: the
/// same "one-time cost either way" tradeoff `UciChainApi` already makes for
/// its own "fetch everything, filter client-side" model.
class WebticChainApi implements ChainApi {
  WebticChainApi(this._client);

  final WebticPlatformApiClient _client;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async {
    final schedule = await _client.getFullSchedule(
      cinema.host!,
      cinema.webticLocalId!,
    );
    final days = parseWebticShowingDays(schedule);
    return days.map((d) => ShowingDate(date: d, hasShowings: true)).toList();
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async {
    // [day] is unused - getFullSchedule already returns every day at once,
    // same reasoning as UciChainApi.getFilmsForDay (see ChainApi doc).
    final host = cinema.host!;
    final localId = cinema.webticLocalId!;
    final schedule = await _client.getFullSchedule(host, localId);
    final films = parseWebticFullSchedule(schedule);

    final result = <Film>[];
    for (final film in films) {
      if (film.sessionsByDay.isEmpty) continue;
      final showingGroups =
          film.sessionsByDay.entries.map((entry) {
              final sessions =
                  entry.value.map((parsed) {
                      return Session(
                        sessionId: parsed.performanceId,
                        startTime: parsed.startTime,
                        endTime: parsed.endTime,
                        screenName: parsed.screenName,
                        isSoldOut: false,
                        formattedPrice: null,
                        isPriceVisible: false,
                        attributes: const [],
                        // The chain's own quick-booking flow for this exact
                        // showtime (see PROJECT_NOTES.md) - this app never
                        // implements booking itself, it just hands off.
                        bookingPath:
                            'https://$host/generic/seatsframe.php'
                            '?sc=$localId&sp=${parsed.performanceId}'
                            '#seatsframe',
                        webticScreenId: parsed.screenId,
                      );
                    }).toList()
                    ..sort((a, b) => a.startTime.compareTo(b.startTime));
              return ShowingGroup(date: entry.key, sessions: sessions);
            }).toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      result.add(
        Film(
          filmId: film.eventId,
          title: film.title,
          // The poster handler lives on the shared Webtic backend, not the
          // chain's own front-end site the rest of the catalog comes from
          // (confirmed live - see PROJECT_NOTES.md).
          posterImageSrc: film.posterPath == null
              ? null
              : 'https://secure.webtic.it/cvu/modules/${film.posterPath}',
          runningTime: film.runningTimeMinutes,
          showingGroups: showingGroups,
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async {
    final localId = cinema.webticLocalId;
    final screenId = session.webticScreenId;
    if (localId == null || screenId == null) {
      throw ApiException(AppLocalizations.current.seatsLoadError);
    }
    final results = await Future.wait([
      _client.getMapSeats(localId, screenId),
      _client.getOccupancy(localId, session.sessionId),
    ]);
    return compute(
      parseWebticSeatMap,
      WebticSeatMapPayload(
        mapSeatsResponseBody: results[0],
        occupancyResponseBody: results[1],
      ),
    );
  }
}

final webticChainApiProvider = Provider<WebticChainApi>((ref) {
  return WebticChainApi(ref.watch(webticPlatformApiClientProvider));
});
