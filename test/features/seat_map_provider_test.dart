import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/chains/chain_api.dart';
import 'package:thespace_companion/core/chains/chain_registry.dart';
import 'package:thespace_companion/core/models/cinema.dart';
import 'package:thespace_companion/core/models/film.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/core/models/showing_date.dart';
import 'package:thespace_companion/core/network/api_client.dart'
    show ApiException;
import 'package:thespace_companion/features/seat_map/seat_map_provider.dart';

/// A [ChainApi] that returns whatever seat map the test hands it. Overriding
/// `chainApiProvider` this way is enough to exercise the real
/// `seatMapProvider` end to end - no HTTP mocking needed, since every chain
/// reaches the provider through this one interface.
class _FakeChainApi implements ChainApi {
  _FakeChainApi(this.seatMap);

  final SeatMap seatMap;

  @override
  Future<SeatMap> getSeatMap(Cinema cinema, Session session) async => seatMap;

  @override
  Future<List<ShowingDate>> getShowingDates(Cinema cinema) async => const [];

  @override
  Future<List<Film>> getFilmsForDay(Cinema cinema, DateTime day) async =>
      const [];
}

SeatMap _seatMapWithRows(List<SeatRow> rows) => SeatMap(
  screenLabel: '',
  totalRows: rows.length,
  totalColumns: rows.isEmpty ? 0 : rows.first.seats.length,
  rows: rows,
  areaCategories: const [],
);

const _cinema = Cinema(
  cinemaId: 'x',
  name: 'X',
  slug: 'x',
  address: 'Via X 1',
  lat: 0,
  lng: 0,
  chain: CinemaChain.webtic,
);

final _session = Session(
  sessionId: 's1',
  startTime: DateTime(2026, 8, 30, 21),
  endTime: DateTime(2026, 8, 30, 23),
  screenName: 'Sala 1',
  isSoldOut: false,
  formattedPrice: null,
  isPriceVisible: false,
  attributes: const [],
  bookingPath: null,
);

ProviderContainer _containerReturning(SeatMap seatMap) {
  final container = ProviderContainer(
    overrides: [
      chainApiProvider.overrideWith((ref, chain) => _FakeChainApi(seatMap)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('seatMapProvider', () {
    test('a room with seats resolves normally', () async {
      final container = _containerReturning(
        _seatMapWithRows([
          SeatRow(
            rowLabel: 'A',
            rowIndex: 1,
            seats: const [
              Seat(
                rowIndex: 1,
                columnIndex: 1,
                name: 'A1',
                status: SeatStatus.available,
                areaCategoryCode: 'PT',
              ),
            ],
          ),
        ]),
      );

      final seatMap = await container.read(
        seatMapProvider((_cinema, _session)).future,
      );
      expect(seatMap.rows, hasLength(1));
    });

    test(
      'this is the actual regression case: a room that parsed to zero rows '
      'is missing data, not an empty screening - it used to render a blank '
      'grid captioned "Occupati 0/0 - 0%", which reads as "wide open, '
      'plenty of seats". Some venues really do return capienza 0 / posti [] '
      'for every performance (see PROJECT_NOTES.md), so this must surface '
      'as an error the user can retry, never as a plausible-looking empty room',
      () async {
        final container = _containerReturning(_seatMapWithRows(const []));

        // Asserted through the AsyncValue the screen actually watches,
        // rather than through `.future`: with no widget listening, an
        // autoDispose provider can be torn down before `.future` settles,
        // and riverpod then reports its own disposal error instead of the
        // one under test.
        final states = <AsyncValue<SeatMap>>[];
        final sub = container.listen(
          seatMapProvider((_cinema, _session)),
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await pumpEventQueue();

        final settled = states.last;
        expect(settled.hasError, isTrue);
        expect(settled.error, isA<ApiException>());
      },
    );
  });
}
