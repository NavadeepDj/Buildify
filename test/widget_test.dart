import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildify/main.dart';

void main() {
  testWidgets('App renders auth page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BuildifyApp()));
    expect(find.text('buildify'), findsWidgets);
  });
}
