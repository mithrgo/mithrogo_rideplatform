/// Words that describe a kind of place rather than naming one. "railway" and "bus stand" are generic,
/// so they search near the rider. "railway station Hyderabad" names a place, so it also searches across India.
const _genericTerms = {
  'railway', 'railways', 'rail', 'station', 'stations', 'stn', 'junction', 'halt',
  'bus', 'stand', 'stop', 'busstand', 'auto', 'airport',
  'hospital', 'hospitals', 'clinic', 'medical', 'pharmacy', 'chemist',
  'mall', 'market', 'shop', 'shops', 'store', 'ration', 'petrol', 'pump',
  'hotel', 'hotels', 'lodge', 'restaurant', 'cafe', 'dhaba',
  'school', 'college', 'university', 'temple', 'mosque', 'church',
  'bank', 'atm', 'police', 'post', 'office', 'park', 'theatre', 'cinema',
  'gate', 'road', 'hall',
};

/// True when the query contains a word that is not a generic place type, such as a city or locality name.
bool isExplicitPlaceQuery(String query) {
  final tokens = query.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true)).where((t) => t.isNotEmpty);
  return tokens.any((token) => !_genericTerms.contains(token));
}
