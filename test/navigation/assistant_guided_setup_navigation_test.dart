import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:buildify_flutter/pages/projects_home_page.dart';
import 'package:buildify_flutter/pages/ai_model_select_page.dart';
import 'package:buildify_flutter/screens/ai_server_shell.dart';
import 'package:buildify_flutter/screens/network_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'buildify_user_tour_status': '1',
      'buildify_has_completed_guided_tour': '1',
    });
  });

  Widget createTestApp({Widget? home}) {
    return ProviderScope(
      child: MaterialApp(home: home ?? const ProjectsHomePage()),
    );
  }

  Future<void> pumpNavigationTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

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
