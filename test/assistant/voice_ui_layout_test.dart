import 'dart:io';
import 'dart:ui' as ui;

import 'package:buildify_flutter/assistant/setup_controller.dart';
import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/voice_tool_runtime.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/android_voice_screen.dart';
import 'package:buildify_flutter/screens/assistant_setup_screen.dart';
import 'package:buildify_flutter/screens/voice_actions_screen.dart';
import 'package:buildify_flutter/widgets/voice_overlay_visibility.dart';
import 'package:buildify_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _capture = Platform.environment['BUILDIFY_UI_SNAPSHOTS'] == '1';
Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/voice-ui-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_capture) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0), (1100.0, 1.0)]) {
    testWidgets('voice flow at width $width and text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final host = AiServerController(initialize: false);
      final container = ProviderContainer(
        overrides: [
          aiServerProvider.overrideWith((ref) => host),
          assistantSetupProvider.overrideWith(
            (ref) => AssistantSetupController(host),
          ),
          statusProbeProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      final key = GlobalKey();
      Future<void> show(Widget screen) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: key, child: child!),
                  ),
              home: screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await show(const AndroidVoiceScreen());
      await _snapshot(tester, key, 'phone-$width-$scale');
      await tester.tap(find.text('My laptop'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Call to control my laptop'),
        200,
        scrollable:
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
      );
      await _snapshot(tester, key, 'laptop-$width-$scale');
      expect(tester.takeException(), isNull);

      container
          .read(voiceActionsProvider.notifier)
          .request(
            'start_project',
            {'project_id': 'synthetic-project'},
            'Start the saved static website and publish its configured route.',
            localReview:
                'Project: Example portfolio\nUses saved static files. Review before starting.',
          );
      await show(const VoiceActionsScreen());
      await _snapshot(tester, key, 'review-$width-$scale');
      await tester.scrollUntilVisible(
        find.text('View details'),
        200,
        scrollable:
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
      );
      for (
        var attempt = 0;
        find.text('View details').hitTestable().evaluate().isEmpty &&
            attempt < 12;
        attempt++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.text('View details').hitTestable(), findsOneWidget);
      await tester.tap(find.text('View details').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _snapshot(tester, key, 'details-$width-$scale');
      // Close the route before replacing the app under the modal.
      expect(find.byTooltip('Close review'), findsOneWidget);
      await tester.tap(find.byTooltip('Close review'));
      await tester.pumpAndSettle();
      await show(const AssistantSetupScreen());
      await _snapshot(tester, key, 'setup-$width-$scale');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('call screen hides global shortcuts until the route closes', (
    tester,
  ) async {
    final observer = VoiceOverlayRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/voice-call'),
        builder: (_) => const Scaffold(),
      ),
    );
    await tester.pumpAndSettle();
    expect(voiceOverlaysVisible.value, isFalse);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(voiceOverlaysVisible.value, isTrue);
  });
}
