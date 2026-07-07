import '../models/cinema.dart';
import '../models/film.dart';
import '../models/seat_map.dart';
import '../models/showing_date.dart';

/// What every supported chain must be able to answer, in the shared models
/// the UI already knows how to render ([ShowingDate], [Film]/[Session],
/// [SeatMap]) - the screens never see chain-specific data shapes.
///
/// Adding a third chain (or an independent cinema) later means writing one
/// class that implements this, registering it in `chain_registry.dart`, and
/// nothing else: no screen, provider signature, or model touched by the UI
/// needs to change.
abstract class ChainApi {
  Future<List<ShowingDate>> getShowingDates(Cinema cinema);
  Future<List<Film>> getFilmsForCinema(Cinema cinema);

  /// Takes the whole [Session], not just its id: a chain whose seat map
  /// needs more than "which cinema, which session" (UCI also needs the
  /// session's own `webticScreenId`) reads it straight off here instead of
  /// the interface needing a wider, chain-specific parameter list.
  Future<SeatMap> getSeatMap(Cinema cinema, Session session);
}
