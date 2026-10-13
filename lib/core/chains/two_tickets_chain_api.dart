import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../date/clock.dart';
import '../localization/app_localizations.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';
import '../network/api_client.dart' show ApiException;
import '../network/two_tickets_api_client.dart';
import '../util/ttl_cache.dart';
import 'chain_api.dart';
import 'two_tickets/two_tickets_checkout_parser.dart';
import 'two_tickets/two_tickets_seat_map_parser.dart';
import 'two_tickets/two_tickets_venue_parser.dart';

/// [ChainApi] for 2Tickets.it venues.
///
/// A venue's programme costs one venue page plus one checkout page per
/// cinema title (each ~210 KB gzipped) - but each checkout page already
/// holds every on-sale date, so the whole programme is fetched once, cached
/// for [_programmeTtl], and every day/date query is served from it. At most
/// [_maxConcurrent] pages are requested at a time: a small site.
class TwoTicketsChainApi implements ChainApi {
  TwoTicketsChainApi(this._client, Clock clock)
    : _programmes = TtlCache(clock, _programmeTtl);

  static const _programmeTtl = Duration(minutes: 10);
  static const _maxConcurrent = 3;

  final TwoTicketsApiClient _client;
  final TtlCache<String, List<Film>> _programmes;
  final _inFlight = <String, Future<List<Film>>>{};

  Future<List<Film>> _programme(Cinema cinema) {
    final cached = _programmes.get(cinema.cinemaId);
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[cinema.cinemaId];
    if (pending != null) return pending;
    final future = _fetchProgramme(cinema).then((films) {
      _programmes.set(cinema.cinemaId, films);
      return films;
    });
    _inFlight[cinema.cinemaId] = future;
    future.whenComplete(() => _inFlight.remove(cinema.cinemaId)).ignore();
    return future;
  }

  /// Runs [task] over [items] with at most [_maxConcurrent] in flight,
  /// preserving input order in the result.
  static Future<List<R>> _pooled<T, R>(
    List<T> items,
    Future<R> Function(T) task,
  ) async {
    final results = <R>[];
    for (var i = 0; i < items.length; i += _maxConcurrent) {
      final batch = items.skip(i).take(_maxConcurrent);
      results.addAll(await Future.wait(batch.map(task)));
    }
    return results;
  }

  Future<List<Film>> _fetchProgramme(Cinema cinema) async {
    final venue = await compute(
      parseTwoTicketsVenuePage,
      await _client.getVenuePage(cinema.cinemaId),
    );
    final pages = await _pooled(venue.films, (TwoTicketsVenueFilm film) async {
      final html = await _client.getCheckoutPage(film.filmId, cinema.cinemaId);
      return compute(parseTwoTicketsCheckoutPage, html);
    });

    final films = <Film>[];
    for (var i = 0; i < venue.films.length; i++) {
      final film = venue.films[i];
      final page = pages[i];
      final byDay = <DateTime, List<Session>>{};
      for (final p in page.performances) {
        final day = DateTime(
          p.startTime.year,
          p.startTime.month,
          p.startTime.day,
        );
        byDay.putIfAbsent(day, () => []).add(_session(cinema, film, page, p));
      }
      if (byDay.isEmpty) continue;
      final days = byDay.keys.toList()..sort();
      films.add(
        Film(
          filmId: film.filmId,
          title: film.title,
          posterImageSrc: film.posterUrl,
          runningTime: film.runningTime,
          showingGroups: [
            for (final d in days)
              ShowingGroup(
                date: d,
                sessions: byDay[d]!
                  ..sort((a, b) => a.startTime.compareTo(b.startTime)),
              ),
          ],
        ),
      );
    }
    films.sort((a, b) => a.title.compareTo(b.title));
    return films;
  }

  Session _session(
    Cinema cinema,
    TwoTicketsVenueFilm film,
    TwoTicketsCheckoutPage page,
    TwoTicketsPerformance p,
  ) {
    return Session(
      sessionId: p.eventId,
      startTime: p.startTime,
      endTime: p.startTime.add(Duration(minutes: film.runningTime ?? 120)),
      screenName: p.hall,
      isSoldOut: p.isSoldOut,
      formattedPrice: null,
      isPriceVisible: false,
      attributes: [
        if (p.is3D)
          const SessionAttribute(
            name: '3D',
            attributeType: 'screen',
            color: null,
          ),
        if (p.isAtmos)
          const SessionAttribute(
            name: 'ATMOS',
            attributeType: 'screen',
            color: null,
          ),
        // Tagged on every session (like UCI): "ITA" is a default language
        // and stays silent, "VO" gets a caption - see isNotableLanguage.
        SessionAttribute(
          name: p.isOriginalLanguage ? 'VO' : 'ITA',
          attributeType: 'Language',
          color: null,
        ),
      ],
      bookingPath:
          '$twoTicketsBaseUrl/Acquisto/Checkout/${film.filmId}/'
          '${cinema.cinemaId}/${p.eventId}?settore=C&orario=${p.rawTime}',
      twoTicketsServerEse: page.serverEse,
      twoTicketsPortEse: page.portEse,
    );
  }

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) {
    return runChainParsing(() async {
      final films = await _programme(cinema);
      final days = {
        for (final f in films)
          for (final g in f.showingGroups)
            if (g.sessions.isNotEmpty) g.date,
      }.toList()..sort();
      return [for (final d in days) ShowingDate(date: d, hasShowings: true)];
    });
  }

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) {
    // [day] unused: every date arrives together (see class doc).
    return runChainParsing(() => _programme(cinema));
  }

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) {
    return runChainParsing(() async {
      final ese = session.twoTicketsServerEse;
      final port = session.twoTicketsPortEse;
      if (ese == null || port == null) {
        throw ApiException(AppLocalizations.current.seatsLoadError);
      }
      final t = session.startTime;
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      final sectors = parseTwoTicketsSectors(
        await _client.getSectors(
          eventId: session.sessionId,
          time: '$hh:$mm',
          serverEse: ese,
          portEse: port,
        ),
      );
      final numbered = sectors.where((s) => s.isNumbered).toList();
      final bodies = await _pooled(
        numbered,
        (TwoTicketsSector s) => _client.getSeats(
          sectorId: s.id,
          eventId: session.sessionId,
          rawTime: '$hh.$mm',
          serverEse: ese,
          portEse: port,
        ),
      );
      return compute(
        buildTwoTicketsSeatMap,
        TwoTicketsSeatMapPayload(
          sectors: sectors,
          seatsJsonBySectorId: {
            for (var i = 0; i < numbered.length; i++) numbered[i].id: bodies[i],
          },
        ),
      );
    });
  }
}

final twoTicketsChainApiProvider = Provider<TwoTicketsChainApi>((ref) {
  return TwoTicketsChainApi(
    ref.watch(twoTicketsApiClientProvider),
    ref.watch(clockProvider),
  );
});
