import 'package:buildify_flutter/main.dart';
import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/status_probe_server.dart';
import 'package:buildify_flutter/screens/voice_actions_screen.dart';
import 'package:buildify_flutter/services/app_route_observer.dart';
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
    final routeEvents = _RouteEvents();
    final initialRoute =
        ModalRoute.of(tester.element(find.byType(Scaffold).first))!;
    appRouteObserver.subscribe(routeEvents, initialRoute);
    addTearDown(() => appRouteObserver.unsubscribe(routeEvents));
    await tester.tap(find.text('Voice requests'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceActionsScreen), findsOneWidget);
    expect(find.text('Review model setup'), findsOneWidget);
    expect(routeEvents.covered, 1);
    expect(find.text('Voice requests'), findsNothing);
    Navigator.of(tester.element(find.byType(VoiceActionsScreen))).pop();
    await tester.pumpAndSettle();
    expect(routeEvents.revealed, 1);
    expect(find.text('Voice requests'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RouteEvents with RouteAware {
  int covered = 0;
  int revealed = 0;

  @override
  void didPushNext() => covered++;

  @override
  void didPopNext() => revealed++;
}
