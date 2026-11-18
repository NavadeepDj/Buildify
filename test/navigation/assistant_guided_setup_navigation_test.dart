import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:buildify_flutter/backend/embedded_backend.dart';
import 'package:buildify_flutter/pages/projects_home_page.dart';
import 'package:buildify_flutter/pages/ai_model_select_page.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/ai_server_shell.dart';
import 'package:buildify_flutter/screens/network_screen.dart';
import 'package:buildify_flutter/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'buildify_user_tour_status': '1',
      'buildify_has_completed_guided_tour': '1',
      'buildify_tour_ai_shell': '1',
    });
  });

  Widget createTestApp({
    Widget? home,
    List<BackendProject> projects = const [],
  }) {
    return ProviderScope(
      overrides: [
        embeddedBackendProvider.overrideWith((ref) {
          final backend = EmbeddedBackendService(autoHydrate: false);
          ref.onDispose(backend.dispose);
          return backend;
        }),
        backendProjectsProvider.overrideWith((ref) => Stream.value(projects)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: home ?? const ProjectsHomePage(),
      ),
    );
  }

  Future<void> pumpNavigationTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  BackendProject project(String name, {bool running = false}) => BackendProject(
    id: name,
    name: name,
    repoProvider: 'Static',
    url: '',
    lastDeployedAt: null,
    isLive: running,
  );

  testWidgets('projects dashboard settles at rest and after a phone scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      createTestApp(
        projects: [project('First project'), project('Second project')],
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(find.text('First project'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(find.text('new service').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'dashboard search and Running filter can recover from no matches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        createTestApp(
          projects: [project('Atlas', running: true), project('Beacon')],
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byType(TextField);

      await tester.enterText(search, '  bEAcON ');
      await tester.pumpAndSettle();
      expect(find.text('Beacon'), findsOneWidget);
      expect(find.text('Atlas'), findsNothing);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('No matching running services'), findsOneWidget);
      await tester.tap(find.text('Reset search and filter'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.text('Beacon'), findsOneWidget);
      expect(find.text('Atlas'), findsOneWidget);

      await tester.tap(find.text('Running'));
      await tester.pumpAndSettle();
      expect(find.text('Atlas'), findsOneWidget);
      expect(find.text('Beacon'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.enterText(search, 'Unknown');
      await tester.pumpAndSettle();
      expect(find.text('No matching services'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Beacon'), findsOneWidget);
      expect(find.text('Atlas'), findsOneWidget);
    },
  );

  testWidgets('dashboard distinguishes stopped services from an empty list', (
    tester,
  ) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();
    expect(find.text('No services yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(createTestApp(projects: [project('Beacon')]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(find.text('No running services'), findsOneWidget);
    expect(find.text('No services yet'), findsNothing);
    await tester.tap(find.text('Show all services'));
    await tester.pumpAndSettle();
    expect(find.text('Beacon'), findsOneWidget);
  });

  group('Issue #145: Assistant Guided Setup Navigation Integration', () {
    testWidgets(
      'Navigates from ProjectsHomePage modal to AiServerShell and Network controls',
      (WidgetTester tester) async {
        // 1. Start on the actual app route (ProjectsHomePage)
        await tester.pumpWidget(createTestApp());
        await pumpNavigationTransition(tester);

        // 2. Scroll to the new service button below the project list.
        final newServiceButton = find.text('new service');
        await tester.scrollUntilVisible(
          newServiceButton,
          200,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.tap(newServiceButton.hitTestable());
        await pumpNavigationTransition(tester);

        // 3. Verify modal options
        expect(find.text('select service type'), findsOneWidget);
        expect(find.text('host a project'), findsOneWidget);
        expect(find.text('model setup assistant'), findsOneWidget);
        expect(find.text('run an ai model'), findsOneWidget);

        // 4. Tap "model setup assistant"
        await tester.tap(find.text('model setup assistant'));
        await pumpNavigationTransition(tester);

        // 5. Verify AiServerShell is reached without modifying source or test-only routes
        expect(find.byType(AiServerShell), findsOneWidget);
        expect(find.text('Buildify AI'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Models'), findsOneWidget);
        expect(find.text('Self test'), findsOneWidget);
        expect(find.text('Network'), findsOneWidget);

        // 6. Navigate to Network tab to verify deliberate public-sharing controls
        await tester.tap(find.text('Network'));
        await pumpNavigationTransition(tester);

        expect(find.byType(NetworkScreen), findsOneWidget);
        expect(find.text('Cloudflare Tunnel'), findsOneWidget);
        expect(find.text('Copy API URL'), findsOneWidget);
      },
    );

    testWidgets('Navigates from AiModelSelectPage banner to AiServerShell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp(home: const AiModelSelectPage()));
      await pumpNavigationTransition(tester);

      // Verify model setup assistant banner is present on the model select page
      expect(find.text('model setup assistant'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);

      // Tap OPEN button
      await tester.tap(find.text('OPEN'));
      await pumpNavigationTransition(tester);

      // Verify AiServerShell is mounted
      expect(find.byType(AiServerShell), findsOneWidget);
    });
  });
}
