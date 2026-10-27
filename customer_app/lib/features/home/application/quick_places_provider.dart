import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/quick_place.dart';

/// The destination cards managed in the admin console. An empty list simply shows no cards.
final quickPlacesProvider = FutureProvider.autoDispose<List<QuickPlace>>((ref) async {
  final response = await ref
      .watch(apiClientProvider)
      .send((dio) => dio.get<List<dynamic>>(ApiEndpoints.quickPlaces));
  return [
    for (final item in response.data ?? const []) ?QuickPlace.tryFromJson(item),
  ];
});
