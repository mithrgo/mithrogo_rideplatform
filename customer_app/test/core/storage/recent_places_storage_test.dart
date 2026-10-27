import 'package:customer_app/core/location/place.dart';
import 'package:customer_app/core/storage/recent_places_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Place _place(String name, {String? id}) =>
    Place(name: name, address: '$name, Nizamabad', latitude: 18.67, longitude: 78.09, id: id);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts empty', () async {
    expect(await RecentPlacesStorage().read(), isEmpty);
  });

  test('puts the newest place first and survives a restart', () async {
    final storage = RecentPlacesStorage();
    await storage.add(_place('Railway Station', id: 'node:1'));
    await storage.add(_place('Bus Stand', id: 'node:2'));

    final names = (await RecentPlacesStorage().read()).map((p) => p.name).toList();
    expect(names, ['Bus Stand', 'Railway Station']);
  });

  test('choosing a saved place again moves it to the top without repeating it', () async {
    final storage = RecentPlacesStorage();
    await storage.add(_place('Railway Station', id: 'node:1'));
    await storage.add(_place('Bus Stand', id: 'node:2'));
    final updated = await storage.add(_place('Railway Station', id: 'node:1'));

    expect(updated.map((p) => p.name), ['Railway Station', 'Bus Stand']);
  });

  test('keeps only the latest ${RecentPlacesStorage.maxPlaces}', () async {
    final storage = RecentPlacesStorage();
    for (var i = 0; i < 12; i++) {
      await storage.add(_place('Place $i', id: 'node:$i'));
    }
    final saved = await storage.read();
    expect(saved, hasLength(RecentPlacesStorage.maxPlaces));
    expect(saved.first.name, 'Place 11');
  });

  test('clear empties the list, and damaged data reads as empty', () async {
    final storage = RecentPlacesStorage();
    await storage.add(_place('Railway Station', id: 'node:1'));
    await storage.clear();
    expect(await storage.read(), isEmpty);

    FlutterSecureStorage.setMockInitialValues({'recent_places': 'not json'});
    expect(await RecentPlacesStorage().read(), isEmpty);
  });
}
