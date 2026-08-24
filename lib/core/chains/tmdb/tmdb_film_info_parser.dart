import 'dart:convert';

/// TMDb has never heard of the " · {label}" suffix this app itself appends
/// to disambiguate duplicate 18tickets titles (see
/// eighteen_tickets_film_parser.dart's `_disambiguateDuplicateTitles`) - it
/// isn't part of the real film title, so it's stripped before searching.
String cleanTitleForSearch(String title) {
  final separatorIndex = title.indexOf(' · ');
  return separatorIndex == -1 ? title : title.substring(0, separatorIndex);
}

/// The one TMDb search result this app actually needs: enough to fetch the
/// trailer separately ([id]) and to show a plot right away ([overview]).
class TmdbSearchResult {
  const TmdbSearchResult({required this.id, required this.overview});

  final int id;
  final String overview;
}

/// The first (most relevant, per TMDb's own ranking) search result, or
/// `null` when there are no results or the top one has no overview at all -
/// treated as "no usable match" rather than showing an empty description.
TmdbSearchResult? parseTmdbSearchResult(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final results = decoded['results'] as List<dynamic>? ?? const [];
  if (results.isEmpty) return null;
  final first = results.first as Map<String, dynamic>;
  final overview = (first['overview'] as String?) ?? '';
  if (overview.isEmpty) return null;
  return TmdbSearchResult(id: first['id'] as int, overview: overview);
}

/// The YouTube trailer key to build `https://www.youtube.com/watch?v={key}`
/// from, or `null` if this film has no YouTube video of type Trailer at
/// all. Prefers one flagged `official` when more than one exists.
String? parseTmdbTrailerKey(String responseBody) {
  final decoded = json.decode(responseBody) as Map<String, dynamic>;
  final videos = (decoded['results'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer')
      .toList();
  if (videos.isEmpty) return null;
  final chosen = videos.firstWhere(
    (v) => v['official'] == true,
    orElse: () => videos.first,
  );
  return chosen['key'] as String?;
}
