class Cinema {
  const Cinema({
    required this.cinemaId,
    required this.name,
    required this.slug,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory Cinema.fromJson(Map<String, dynamic> json) {
    return Cinema(
      cinemaId: json['cinemaId'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  final String cinemaId;
  final String name;
  final String slug;
  final String address;
  final double lat;
  final double lng;
}
