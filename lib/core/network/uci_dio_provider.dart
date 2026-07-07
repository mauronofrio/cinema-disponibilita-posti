import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UCI's own content backend (movies/theatres/programming) - confirmed live
/// to need no cookies/auth at all, unlike thespacecinema.it which at least
/// wants a warmed-up cookie jar. See PROJECT_NOTES.md.
const myUciBaseUrl =
    'https://myuci---uci-backend-production-nfluwp7wga-oc.a.run.app/api';

/// The WebTic ticketing platform proxy UCI's booking flow sits on top of.
/// `Screen`/`Occupancy` are confirmed live to respond with no auth of any
/// kind - the personal-account JWT seen in a real booking session's network
/// traffic is only ever attached to the `Performance` call, not these two.
const webTicBaseUrl =
    'https://uci-website-webtic-proxy-production-1042268733238.europe-west8.run.app/Api2';

final myUciDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(baseUrl: myUciBaseUrl, headers: {'Accept': 'application/json'}),
  );
});

final webTicDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: webTicBaseUrl,
      headers: {'Content-Type': 'application/json'},
    ),
  );
});
