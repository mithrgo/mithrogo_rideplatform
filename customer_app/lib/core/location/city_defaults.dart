import 'lat_lng.dart';

/// Nizamabad city centre. Used only as a map viewport and a search bias when GPS is unavailable.
/// It is never used as the rider's position.
const nizamabadCenter = LatLng(latitude: 18.6725, longitude: 78.0941);

/// Shown in the UI when the search falls back to Nizamabad.
const nizamabadLabel = 'Nizamabad, Telangana, India';

/// Half the side of the search-bias box, in degrees (about 55 km north-south at this latitude).
const searchBiasHalfSpanDegrees = 0.5;
