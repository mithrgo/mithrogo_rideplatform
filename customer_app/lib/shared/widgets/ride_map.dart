import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../app/config/env.dart';
import '../../app/theme/app_colors.dart';
import '../../core/location/city_defaults.dart';
import '../../core/location/lat_lng.dart';
import '../../core/routing/route_service.dart';

/// OpenStreetMap view with pickup, drop, the device's position and the driving route.
///
/// Tiles come from [Env.mapTileUrl]. Callers only pass coordinates, so the tile provider can change later.
class RideMap extends StatefulWidget {
  const RideMap({
    super.key,
    this.pickup,
    this.drop,
    this.deviceLocation,
    this.route,
    this.onMapTap,
  });

  final LatLng? pickup;
  final LatLng? drop;

  /// The rider's GPS position, shown as a blue dot.
  final LatLng? deviceLocation;
  final RouteResult? route;

  /// Called with the tapped point. Null means taps do nothing.
  final ValueChanged<LatLng>? onMapTap;

  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> {
  // Room for the top pill and the bottom sheet, so fitted points stay visible.
  static const _fitPadding = EdgeInsets.fromLTRB(56, 150, 56, 340);

  final MapController _controller = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(RideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refit only when the things to show change. Pan and zoom never reach here.
    final selectionChanged = oldWidget.pickup != widget.pickup ||
        oldWidget.drop != widget.drop ||
        !identical(oldWidget.route, widget.route);
    // A late GPS fix must not pull the camera away from a destination the rider already chose.
    final lateDeviceFix = oldWidget.deviceLocation != widget.deviceLocation && widget.drop == null;
    if (_ready && (selectionChanged || lateDeviceFix)) _fit();
  }

  void _fit() {
    final route = widget.route;
    final points = route != null
        ? route.points
        : [widget.pickup, widget.drop].whereType<LatLng>().toList();

    if (points.isEmpty) {
      final device = widget.deviceLocation;
      if (device != null) _controller.move(_toLl(device), 15);
      return;
    }
    if (points.length == 1) {
      _controller.move(_toLl(points.first), 15);
      return;
    }
    _controller.fitCamera(CameraFit.coordinates(
      coordinates: [for (final point in points) _toLl(point)],
      padding: _fitPadding,
      maxZoom: 16,
    ));
  }

  // With no GPS fix and no selection, the viewport opens on Nizamabad. That is a view, not a rider position.
  LatLng get _initialCenter =>
      widget.pickup ?? widget.deviceLocation ?? widget.drop ?? nizamabadCenter;

  bool get _hasAnyPoint =>
      widget.pickup != null || widget.drop != null || widget.deviceLocation != null;

  static ll.LatLng _toLl(LatLng point) => ll.LatLng(point.latitude, point.longitude);

  static Future<void> _openCopyright() {
    return launchUrl(
      Uri.parse('https://www.openstreetmap.org/copyright'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup;
    final drop = widget.drop;
    final device = widget.deviceLocation;
    final route = widget.route;

    final markers = <Marker>[
      // A blue dot for the device, unless the pickup already sits on it.
      if (device != null && device != pickup)
        Marker(
          point: _toLl(device),
          width: 22,
          height: 22,
          child: const _DeviceDot(),
        ),
      if (pickup != null)
        Marker(
          point: _toLl(pickup),
          width: 40,
          height: 44,
          alignment: Alignment.topCenter,
          child: const _Pin(icon: Icons.trip_origin, color: AppColors.success, tooltip: 'Pickup'),
        ),
      if (drop != null)
        Marker(
          point: _toLl(drop),
          width: 40,
          height: 44,
          alignment: Alignment.topCenter,
          child: const _Pin(icon: Icons.location_on, color: AppColors.danger, tooltip: 'Drop-off'),
        ),
    ];

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _toLl(_initialCenter),
        // City-level zoom for the Nizamabad fallback, street-level for a known point.
        initialZoom: _hasAnyPoint ? 15 : 13,
        minZoom: 3,
        maxZoom: 19,
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onTap: widget.onMapTap == null
            ? null
            : (_, point) => widget.onMapTap!(LatLng(
                  latitude: point.latitude,
                  longitude: point.longitude,
                )),
      ),
      children: [
        TileLayer(
          urlTemplate: Env.mapTileUrl,
          userAgentPackageName: Env.mapUserAgent,
        ),
        if (route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final point in route.points) _toLl(point)],
                strokeWidth: 5,
                color: AppColors.ink,
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              '© OpenStreetMap contributors',
              onTap: _openCopyright,
            ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color, required this.tooltip});

  final IconData icon;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 40, shadows: const [
        Shadow(color: Colors.black38, blurRadius: 6),
      ]),
    );
  }
}

class _DeviceDot extends StatelessWidget {
  const _DeviceDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.info,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
    );
  }
}
