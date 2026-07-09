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

  /// A cinema chain whose own front-end site talks to the "Webtic" ticketing
  /// platform for its catalog, then hands off seat map/occupancy to the same
  /// shared `secure.webtic.it` backend UCI also sits on top of - see
  /// [Cinema.host] and [Cinema.webticLocalId]. Not every Webtic-branded chain
  /// exposes its catalog the same way though - see [WebticCatalogSource] and
  /// PROJECT_NOTES.md. Chains with no confirmed working catalog source at all
  /// (Cinelandia, Starplex, Cinestar, ePlanet Cinemas - all Angular SPAs or
  /// session-gated backends with no endpoint crackable from the outside)
  /// aren't supported - only add a cinema here once its own chain's actual
  /// catalog source has been confirmed live.
  webtic;

  static CinemaChain fromJson(String? value) => switch (value) {
    'uci' => CinemaChain.uci,
    'eighteenTickets' => CinemaChain.eighteenTickets,
    'webtic' => CinemaChain.webtic,
    _ => CinemaChain.theSpace,
  };
}

/// [CinemaChain.webtic] only: which of this platform's several different
/// catalog-reading strategies a given chain's own front-end needs (see
/// PROJECT_NOTES.md for how each was discovered) - the shared
/// `secure.webtic.it` seat map/occupancy backend never changes, only how a
/// cinema's showtimes are found in the first place.
enum WebticCatalogSource {
  /// Notorious Cinemas, Il Regno del Cinema: one
  /// `cvu/modules/prenoRapido.php?sel=getFullSched` call per cinema returns
  /// its entire catalog - every film, day and showtime - at once.
  fullSchedule,

  /// Giometti Cinema: each cinema has its own `programmazione` page (at
  /// `https://{host}/cinema/{slug}/programmazione`, see [Cinema.slug])
  /// listing every film currently showing there, but - confirmed live -
  /// only ever *one* calendar day's showtimes per film (today's, or its
  /// next playing day if not showing today), never a full week.
  programmingPage,

  /// Cineplexx (Bolzano/Algo): the chain's own homepage embeds the full
  /// film catalog plus, per film, which of the chain's cinemas show it and
  /// on which calendar days (`data-prog_{siteCinemaId}`, [Cinema.slug]
  /// holding that per-venue numeric id) - but not the individual showtimes
  /// themselves. Those live on each film's own per-cinema page
  /// (`/scheda/{filmSlug}/{filmId}/{siteCinemaId}/`), which - unlike
  /// Giometti - does give a full week at once, just one request per film
  /// rather than one per cinema.
  filmSchedulePages,

  /// A handful of small independent venues (Nuovo Eden - Brescia, Cinema
  /// Mignon/Multisala Cinecity - Mantova's sister sites, Cinema Ducale and
  /// Arcobaleno Film Center - Milano, Orfeo Multisala - Milano, Plinius
  /// Multisala - Milano) whose own front-end sites don't run the classic
  /// `cvu/modules` front end at all - they just deep-link straight to the
  /// `www.webtic.it` Angular booking SPA. That SPA itself gets its catalog
  /// from a *different* shared backend than [fullSchedule]
  /// (`restapi.webtic.it/Webtic/CallOldWebtic`, wrapping the same
  /// `getFullScheduling` call in a JSON-RPC-style envelope) - but confirmed
  /// live to return the exact same `DS.Scheduling.Events[]` shape, so no new
  /// parser was needed, only a new request shape (see
  /// `getFullScheduleViaPortal`). [Cinema.host] is irrelevant for this
  /// source (kept null or set to the venue's own informational site) since
  /// every call here only ever needs [Cinema.webticLocalId].
  fullSchedulePortal,

  /// "Madison Cinemas" (Iglesias, Roma, Grottaferrata/Al Fellini, Pianoro -
  /// Bologna): same one-day-per-film limitation as [programmingPage], but a
  /// completely different WordPress page template - own splitter, own
  /// booking-link shape with no `sc=`/`se=` params at all (just
  /// `/info-e-acquisto/?performance={id}`), own day format - see
  /// `webtic_madison_programming_page_parser.dart`. [Cinema.slug] here is
  /// the venue's own full page slug (e.g.
  /// "programmazione-cinema-madison-roma"), not a `/cinema/{slug}/...` path
  /// segment like Giometti's.
  madisonProgrammingPage;

  static WebticCatalogSource fromJson(String? value) => switch (value) {
    'programmingPage' => WebticCatalogSource.programmingPage,
    'filmSchedulePages' => WebticCatalogSource.filmSchedulePages,
    'fullSchedulePortal' => WebticCatalogSource.fullSchedulePortal,
    'madisonProgrammingPage' => WebticCatalogSource.madisonProgrammingPage,
    _ => WebticCatalogSource.fullSchedule,
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
    this.webticCatalogSource = WebticCatalogSource.fullSchedule,
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
      webticCatalogSource: WebticCatalogSource.fromJson(
        json['webticCatalogSource'] as String?,
      ),
    );
  }

  final String cinemaId;
  final String name;

  /// Mostly unused at runtime (kept for The Space, whose scraper stores it
  /// but whose actual API calls only ever need [cinemaId]) - the exceptions
  /// are [WebticCatalogSource.programmingPage] cinemas, where this is the
  /// URL path segment identifying the venue on its own chain's site (e.g.
  /// "multiplex-pesaro" in `.../cinema/multiplex-pesaro/programmazione`),
  /// and [WebticCatalogSource.filmSchedulePages] cinemas, where it's instead
  /// the venue's own numeric site-internal id (e.g. "2360" for Cineplexx
  /// Bolzano) used to build `/scheda/{filmSlug}/{filmId}/{slug}/` - a
  /// different, chain-assigned number from [webticLocalId], which is what
  /// the shared Webtic backend itself uses.
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

  /// [CinemaChain.webtic] only - see [WebticCatalogSource] for what each
  /// value means and how `WebticChainApi` branches on it.
  final WebticCatalogSource webticCatalogSource;

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
