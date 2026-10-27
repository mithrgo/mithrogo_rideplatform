import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:captain_app/app/app.dart';
import 'package:captain_app/app/providers.dart';
import 'package:captain_app/core/storage/token_storage.dart';

class _EmptyTokenStorage extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('signed-out captain lands on the login screen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tokenStorageProvider.overrideWithValue(_EmptyTokenStorage())],
      child: const App(),
    ));
    // The splash stays up for at least its minimum duration before the router moves on.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Drive with MithrGo'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send code'), findsOneWidget);
  });
}
