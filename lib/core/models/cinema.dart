/// Which chain a [Cinema] belongs to, and therefore which API client/adapter
/// pair knows how to fetch its showtimes and seat maps.
enum CinemaChain {
  theSpace,
  uci,

  /// Not a chain in the branding sense: every cinema with this value is its
  /// own small, independent venue that happens to run its booking site on
  /// the shared "18tickets.net" platform (e.g. RedCarpet Cinema - Monopoli,
  /// Multicinema Galleria - Bari) - confirmed live to be byte-for-byte
  /// compatible with the same parsing code, so one [ChainApi] implementation
  /// serves all of them, distinguished only by their own [Cinema.host].
  eighteenTickets,

  /// A cinema chain whose own front-end site calls the "Webtic" ticketing
  /// platform's classic `cvu/modules/prenoRapido.php` endpoints directly for
  /// its catalog (confirmed live for Notorious Cinemas), then hands off
  /// seat map/occupancy to the same shared `secure.webtic.it` backend UCI
  /// also sits on top of - see [Cinema.host] and [Cinema.webticLocalId].
  /// Not every Webtic-branded chain uses this same front-end pattern though
  /// (Cinelandia, Giometti Cinema and Arcadia Cinema all 404 on it, see
  /// PROJECT_NOTES.md) - only add a cinema here once its own chain's
  /// `prenoRapido.php` has been confirmed live.
  webtic;

  static CinemaChain fromJson(String? value) => switch (value) {
    'uci' => CinemaChain.uci,
    'eighteenTickets' => CinemaChain.eighteenTickets,
    'webtic' => CinemaChain.webtic,
    _ => CinemaChain.theSpace,
  };
}

class Cinema {
  const Cinema({
    required this.cinemaId,
    required this.name,
    required this.slug,
    required this.address,
    required this.lat,
    required this.lng,
    this.chain = CinemaChain.theSpace,
    this.webticLocalId,
    this.host,
    this.hasSeatMap = true,
    this.scheduleFromFilmPages = false,
  });

  factory Cinema.fromJson(Map<String, dynamic> json) {
    return Cinema(
      cinemaId: json['cinemaId'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      chain: CinemaChain.fromJson(json['chain'] as String?),
      webticLocalId: json['webticLocalId'] as int?,
      host: json['host'] as String?,
      hasSeatMap: json['hasSeatMap'] as bool? ?? true,
      scheduleFromFilmPages: json['scheduleFromFilmPages'] as bool? ?? false,
    );
  }

  final String cinemaId;
  final String name;
  final String slug;
  final String address;
  final double lat;
  final double lng;
  final CinemaChain chain;

  /// The id the shared "Webtic" ticketing backend uses for this venue -
  /// called `IDWEBTIC` on [CinemaChain.webtic] chains' own `getCinema` list
  /// and `LocalId` in every `secure.webtic.it` call. For [CinemaChain.uci]
  /// this is the same concept via its own English-translating proxy in
  /// front of the same backend (see `webtic_api_client.dart`) - unrelated
  /// to [cinemaId] there (which is the myuci content backend's own slug).
  final int? webticLocalId;

  /// The per-venue/per-chain hostname every call for this cinema goes to:
  /// for [CinemaChain.eighteenTickets] its own dedicated 18tickets.net
  /// booking site (e.g. "monopoli.redcarpetcinema.it", one deployment per
  /// venue); for [CinemaChain.webtic] the chain's own front-end site shared
  /// by every venue of that chain (e.g. "www.notoriouscinemas.it", one
  /// deployment per *chain*, distinguished venue-to-venue only by
  /// [webticLocalId]).
  final String? host;

  /// False for a cinema whose site only exposes the film programme (titles,
  /// days, and - when present - showtimes), with no working seat-level
  /// booking to send the user on to. Not currently set for any cinema (see
  /// [scheduleFromFilmPages] for the one 18tickets venue that looked like
  /// this at first but turned out to have real, bookable seat maps once its
  /// showtimes were found the right way) - kept for a genuinely booking-less
  /// venue if one ever turns up. The app still shows the programme for
  /// these, just without a seat map to open (a session's time chip is
  /// informational only, not tappable).
  final bool hasSeatMap;

  /// [CinemaChain.eighteenTickets] only, and only Multisala Massimo - Lecce
  /// so far: true for a venue whose `fetch_films` day-by-day calendar never
  /// renders any showtime markup at all (confirmed live, every date checked)
  /// even though its film catalog and individual showtimes are real and
  /// bookable - each film's own overview page (`/film/{filmId}`) still lists
  /// every one of its real showtimes, just not through the calendar view
  /// every other 18tickets venue relies on. When true,
  /// `EighteenTicketsChainApi` falls back to reading showtimes off of that
  /// page instead, one request per film in the catalog rather than the
  /// usual one request per day - deliberately capped to just today and
  /// tomorrow (see `getShowingDates`) given this platform's aggressive
  /// per-IP rate limit (see PROJECT_NOTES.md).
  final bool scheduleFromFilmPages;

  /// [name] alone for UCI Cinemas and every 18tickets/Webtic venue (all
  /// already self-identifying, e.g. "UCI Cinemas Seven Gioia del Colle",
  /// "Red Carpet Cinema - Monopoli" or "Notorious Cinemas - Cagliari"), but
  /// The Space's own names are bare town names ("Casamassima", "Beinasco")
  /// with nothing marking the chain - prefixed here so a mixed list of all
  /// chains stays unambiguous.
  String get displayName => switch (chain) {
    CinemaChain.theSpace => 'The Space $name',
    CinemaChain.uci => name,
    CinemaChain.eighteenTickets => name,
    CinemaChain.webtic => name,
  };

  /// A cinema is the same cinema iff same id within the same chain (ids are
  /// namespaced per chain, e.g. numeric for The Space, slugs for UCI) -
  /// standard entity-identity equality, not a value comparison of every
  /// field. Used as a Riverpod provider key (showtimes/seat map providers
  /// are keyed by [Cinema] itself), so this also needs to hold across
  /// separately-parsed instances of "the same" cinema, not just the same
  /// object reference.
  @override
  bool operator ==(Object other) =>
      other is Cinema && other.cinemaId == cinemaId && other.chain == chain;

  @override
  int get hashCode => Object.hash(cinemaId, chain);
}
