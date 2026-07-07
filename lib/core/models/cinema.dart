/// Which chain a [Cinema] belongs to, and therefore which API client/adapter
/// pair knows how to fetch its showtimes and seat maps.
enum CinemaChain {
  theSpace,
  uci;

  static CinemaChain fromJson(String? value) => switch (value) {
    'uci' => CinemaChain.uci,
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
    );
  }

  final String cinemaId;
  final String name;
  final String slug;
  final String address;
  final double lat;
  final double lng;
  final CinemaChain chain;

  /// UCI Cinemas only: the id its WebTic booking backend uses for this
  /// venue - unrelated to [cinemaId] (which is the myuci content backend's
  /// slug for this chain). Needed for the `Screen`/`Occupancy` calls.
  final int? webticLocalId;

  /// [name] alone for UCI Cinemas (already self-identifying, e.g. "UCI
  /// Cinemas Seven Gioia del Colle"), but The Space's own names are bare
  /// town names ("Casamassima", "Beinasco") with nothing marking the chain -
  /// prefixed here so a mixed list of both chains stays unambiguous.
  String get displayName => switch (chain) {
    CinemaChain.theSpace => 'The Space $name',
    CinemaChain.uci => name,
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
