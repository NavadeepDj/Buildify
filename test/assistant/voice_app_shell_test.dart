import 'package:buildify_flutter/main.dart';
import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/status_probe_server.dart';
import 'package:buildify_flutter/screens/voice_actions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enabled voice bridge renders without Flutter errors', (
    tester,
  ) async {
    final server = await tester.runAsync(
      () => StatusProbeServer.start(
        token: 'synthetic-root-shell-test-token-12345',
        port: 0,
        inspect: () async => {},
      ),
    );
    addTearDown(() async {
      await server!.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [statusProbeProvider.overrideWith((ref) async => server)],
        child: const BuildifyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Navigator), findsWidgets);
    await tester.tap(find.text('Voice requests'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceActionsScreen), findsOneWidget);
    expect(find.text('Review model setup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
