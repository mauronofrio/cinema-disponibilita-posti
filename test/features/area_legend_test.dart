import 'package:flutter_test/flutter_test.dart';
import 'package:thespace_companion/core/models/seat_map.dart';
import 'package:thespace_companion/features/seat_map/widgets/area_legend.dart';

SeatMap _seatMapWith(List<Seat?> seats, List<AreaCategory> categories) {
  return SeatMap(
    screenLabel: '',
    totalRows: 1,
    totalColumns: seats.length,
    rows: [SeatRow(rowLabel: 'A', rowIndex: 1, seats: seats)],
    areaCategories: categories,
  );
}

void main() {
  group('visibleAreaCategories', () {
    test('a category with an available seat is included', () {
      final category = const AreaCategory(
        code: 'PT',
        name: 'Classic',
        color: 'ED6A2C',
        isSoldOut: false,
      );
      final seatMap = _seatMapWith([
        Seat(
          rowIndex: 1,
          columnIndex: 1,
          name: 'A1',
          status: SeatStatus.available,
          areaCategoryCode: 'PT',
        ),
      ], [category]);

      expect(visibleAreaCategories(seatMap), [category]);
    });

    test(
      'this is the actual regression case: a category whose only seats are '
      'accessibility never gets its own legend swatch - confirmed live at '
      'UCI Bicocca Milano, where the "SEDIA A ROTELLE" sector\'s two seats '
      'are both flagged DISABILE and so always render purple with the '
      'wheelchair icon, never that sector\'s own light grey',
      () {
        final wheelchairSector = const AreaCategory(
          code: 'UN',
          name: 'SEDIA A ROTELLE',
          color: 'DCDCDC',
          isSoldOut: false,
        );
        final seatMap = _seatMapWith([
          Seat(
            rowIndex: 1,
            columnIndex: 1,
            name: 'A1',
            status: SeatStatus.accessibility,
            areaCategoryCode: 'UN',
            isAccessibility: true,
          ),
        ], [wheelchairSector]);

        expect(visibleAreaCategories(seatMap), isEmpty);
      },
    );

    test(
      'a category with a mix of available and accessibility seats is still '
      'included, since some of its seats do show its own color',
      () {
        final category = const AreaCategory(
          code: 'PT',
          name: 'Classic',
          color: 'ED6A2C',
          isSoldOut: false,
        );
        final seatMap = _seatMapWith([
          Seat(
            rowIndex: 1,
            columnIndex: 1,
            name: 'A1',
            status: SeatStatus.available,
            areaCategoryCode: 'PT',
          ),
          Seat(
            rowIndex: 1,
            columnIndex: 2,
            name: 'A2',
            status: SeatStatus.accessibility,
            areaCategoryCode: 'PT',
            isAccessibility: true,
          ),
        ], [category]);

        expect(visibleAreaCategories(seatMap), [category]);
      },
    );

    test('a category with no seats at all is excluded', () {
      final unusedCategory = const AreaCategory(
        code: 'ZZ',
        name: 'Unused',
        color: 'FFFFFF',
        isSoldOut: false,
      );
      final seatMap = _seatMapWith([
        Seat(
          rowIndex: 1,
          columnIndex: 1,
          name: 'A1',
          status: SeatStatus.available,
          areaCategoryCode: 'PT',
        ),
      ], [unusedCategory]);

      expect(visibleAreaCategories(seatMap), isEmpty);
    });
  });
}
