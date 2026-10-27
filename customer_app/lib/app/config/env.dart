/// Build-time configuration. Override per build with --dart-define.
///
/// Example: flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1/
class Env {
  const Env._();

  /// Default points at the Django dev server from an Android emulator.
  /// iOS simulators and desktop use http://127.0.0.1:8000/api/v1/ instead.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1/',
  );

  /// OpenStreetMap tiles, for development and light testing only.
  /// Replace with a production tile provider before release.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Sent with tile requests, as the OpenStreetMap tile usage policy asks.
  static const String mapUserAgent = 'com.example.customer_app';

  /// OSRM public demo server. Not guaranteed for production; point this at your own OSRM later.
  static const String osrmBaseUrl = String.fromEnvironment(
    'OSRM_BASE_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  /// Nominatim geocoding, for destination search. The public server has a usage policy:
  /// about one request per second, identifying User-Agent, and no bulk or heavy use.
  static const String nominatimBaseUrl = String.fromEnvironment(
    'NOMINATIM_BASE_URL',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  /// Overpass API, for "mapped features near a point" (stations, bus stations, hospitals).
  /// The public instance is shared and rate-limited (about 10,000 requests a day, and it returns
  /// HTTP 429 when busy). Fine for development. Production needs a self-hosted or paid instance.
  static const String overpassBaseUrl = String.fromEnvironment(
    'OVERPASS_BASE_URL',
    defaultValue: 'https://overpass-api.de/api/interpreter',
  );

  /// Identifies the app to Nominatim and Overpass, as their usage policies require.
  /// Add a contact address for production.
  static const String searchUserAgent = 'MithrGo-CustomerApp/1.0';

  /// Radius, in metres, of the nearby search around the rider's GPS position.
  /// Results beyond it are only shown after the rider chooses to expand the search.
  static const int localSearchRadiusMeters = int.fromEnvironment(
    'LOCAL_SEARCH_RADIUS_METERS',
    defaultValue: 30000,
  );

  /// Radius, in metres, used by "Expand search area" for mapped-feature searches.
  static const int expandedSearchRadiusMeters = int.fromEnvironment(
    'EXPANDED_SEARCH_RADIUS_METERS',
    defaultValue: 100000,
  );

  /// Longest driving distance a ride can have, in metres. Checked on the OSRM route, not straight-line.
  static const int maxRideDistanceMeters = int.fromEnvironment(
    'MAX_RIDE_DISTANCE_METERS',
    defaultValue: 50000,
  );
}
