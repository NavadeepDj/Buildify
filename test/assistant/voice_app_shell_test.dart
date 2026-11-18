import 'package:buildify_flutter/main.dart';
import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/status_probe_server.dart';
import 'package:buildify_flutter/backend/embedded_backend.dart';
import 'package:buildify_flutter/pages/projects_home_page.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/voice_actions_screen.dart';
import 'package:buildify_flutter/services/app_route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Android can scroll new service above both voice shortcuts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({
        'buildify_user_tour_status': '1',
        'buildify_has_completed_guided_tour': '1',
      });
      final server = await tester.runAsync(
        () => StatusProbeServer.start(
          token: 'synthetic-dashboard-test-token-123456',
          port: 0,
          inspect: () async => {},
        ),
      );
      addTearDown(() async => server!.close());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statusProbeProvider.overrideWith((ref) async => server),
            embeddedBackendProvider.overrideWith((ref) {
              final backend = EmbeddedBackendService(autoHydrate: false);
              ref.onDispose(backend.dispose);
              return backend;
            }),
          ],
          child: const BuildifyApp(),
        ),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pushNamed('/projects');
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(ProjectsHomePage),
        matching: find.byType(ListView),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final newService = find.text('new service');
      final newServiceButton =
          find
              .ancestor(of: newService, matching: find.byType(GestureDetector))
              .first;
      final call = find.widgetWithText(FloatingActionButton, 'Call Buildify');
      final requests = find.widgetWithText(
        FloatingActionButton,
        'Voice requests',
      );
      expect(requests.hitTestable(), findsOneWidget);
      expect(call.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(newServiceButton).bottom,
        lessThan(tester.getTopLeft(call).dy),
      );
      await tester.tap(newService.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('select service type'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

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
