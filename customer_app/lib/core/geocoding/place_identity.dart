import '../location/place.dart';

/// A key that is the same for the same real place, even when two searches return it.
///
/// Uses the OpenStreetMap id when the search gives one. Otherwise it uses the normalised name
/// plus coordinates rounded to about 10 m, so small spelling or case differences still match.
String placeIdentity(Place place) {
  final id = place.id;
  if (id != null) return id;

  final name = place.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  return '$name|${place.latitude.toStringAsFixed(4)}|${place.longitude.toStringAsFixed(4)}';
}

/// Keeps the first place for each identity, in the order given.
List<Place> dedupePlaces(Iterable<Place> places) {
  final seen = <String>{};
  return [
    for (final place in places)
      if (seen.add(placeIdentity(place))) place,
  ];
}
