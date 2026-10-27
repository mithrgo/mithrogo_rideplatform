import '../../app/config/env.dart';
import 'city_defaults.dart';
import 'lat_lng.dart';

/// The app serves India only: phone numbers are +91, and search is limited to country code "in".
/// Coordinates outside this box are not trusted as the rider's pickup.
///
/// The box is a rough bounding box, so points just across a border may pass. It only has to catch
/// emulator or stale fixes that are far away.
bool isInServiceArea(LatLng point) {
  return point.isValid &&
      point.latitude >= 6.5 &&
      point.latitude <= 37.5 &&
      point.longitude >= 68.0 &&
      point.longitude <= 97.5;
}

/// True when [point] is inside the main city service area (the city centre and its radius).
/// Extra zones added in the backend admin are not known here, so a rider standing in one is
/// treated as outside the city for search purposes only. Booking itself is checked by the server.
bool isInsideCity(LatLng point) {
  return point.isValid && point.distanceTo(nizamabadCenter) <= Env.serviceAreaRadiusMeters;
}

/// Where a nearby search is centred: the rider's GPS position when it is inside the city,
/// otherwise the city centre, so that results are places the rider could actually book.
LatLng searchOriginFor(LatLng gps) => isInsideCity(gps) ? gps : nizamabadCenter;
