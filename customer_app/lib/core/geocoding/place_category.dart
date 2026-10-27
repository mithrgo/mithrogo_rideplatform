/// Kinds of place that are found by their mapped OpenStreetMap tags, not only by their name.
///
/// A name search for "railway" misses most stations, because many are named after their town
/// ("Nizamabad") rather than "Railway Station". Tag search finds every station in the area.
enum PlaceCategory {
  railwayStation('Railway station', [
    ['railway', 'station'],
    ['railway', 'halt'],
  ]),
  busStation('Bus station', [
    ['amenity', 'bus_station'],
  ]),
  hospital('Hospital', [
    ['amenity', 'hospital'],
  ]);

  const PlaceCategory(this.label, this.tags);

  /// Shown when a mapped feature has no name, so the result is not presented as a named place.
  final String label;

  /// OpenStreetMap `[key, value]` pairs. Any one matching feature is a result.
  final List<List<String>> tags;
}

/// The category a query asks for, or null for free-text searches.
///
/// Matching is by word, so "railway station" and "railways" both map to railway stations,
/// but "station" on its own does not.
PlaceCategory? categoryForQuery(String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'[^\p{L}]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toSet();

  if (words.any((w) => const {'railway', 'railways', 'rail', 'train'}.contains(w))) {
    return PlaceCategory.railwayStation;
  }
  if (words.contains('bus')) return PlaceCategory.busStation;
  if (words.any((w) => const {'hospital', 'hospitals'}.contains(w))) {
    return PlaceCategory.hospital;
  }
  return null;
}
