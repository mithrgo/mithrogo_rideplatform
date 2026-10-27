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
