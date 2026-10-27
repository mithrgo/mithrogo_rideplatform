import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:captain_app/app/app.dart';

void main() {
  testWidgets('app starts on splash', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    expect(find.text('MithrGo Captain'), findsOneWidget);
  });
}
