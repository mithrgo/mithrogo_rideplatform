import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../geocoding/place_identity.dart';
import '../location/place.dart';

/// The places the rider chose recently, newest first, kept on the device for quick access.
class RecentPlacesStorage {
  RecentPlacesStorage({FlutterSecureStorage? storage}) : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'recent_places';
  static const maxPlaces = 8;

  final FlutterSecureStorage _storage;

  Future<List<Place>> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) ?Place.tryFromJson(item),
      ];
    } catch (_) {
      // Unreadable history is the same as no history.
      return const [];
    }
  }

  /// Puts [place] first. If it was already saved, the old entry is replaced, not repeated.
  Future<List<Place>> add(Place place) async {
    final current = await read();
    final key = placeIdentity(place);
    final updated = [
      place,
      ...current.where((saved) => placeIdentity(saved) != key),
    ].take(maxPlaces).toList();
    await _write(updated);
    return updated;
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  Future<void> _write(List<Place> places) async {
    try {
      await _storage.write(key: _key, value: jsonEncode([for (final p in places) p.toJson()]));
    } catch (_) {
      // Failing to save history must never block choosing a place.
    }
  }
}
