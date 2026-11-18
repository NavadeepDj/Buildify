import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/voice_bridge_session.dart';
import 'package:buildify_flutter/screens/android_voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disconnect revokes pairing even if native tunnel stop fails', (
    tester,
  ) async {
    const channel = MethodChannel('buildify.ai/voice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'stopTunnel') {
            throw PlatformException(code: 'unavailable');
          }
          return {
            'status': 'running',
            'publicUrl': 'https://test-phone.trycloudflare.com',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer(
      overrides: [statusProbeProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    container.read(voiceBridgeSessionProvider.notifier).enable();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AndroidVoiceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect voice'));
    await tester.pumpAndSettle();
    expect(container.read(voiceBridgeSessionProvider), isNull);
    expect(find.textContaining('Voice pairing revoked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background status polling preserves call-link errors', (
    tester,
  ) async {
    const channel = MethodChannel('buildify.ai/voice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'running',
            'publicUrl': 'https://test-phone.trycloudflare.com',
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer(
      overrides: [statusProbeProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    container.read(voiceBridgeSessionProvider.notifier).enable();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AndroidVoiceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final scroll =
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
    await tester.scrollUntilVisible(
      find.byType(TextField),
      200,
      scrollable: scroll,
    );
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.scrollUntilVisible(
      find.text('Call to control this phone'),
      150,
      scrollable: scroll,
    );
    await tester.tap(find.text('Call to control this phone'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.scrollUntilVisible(
      find.text('Paste the complete private HTTPS call link.'),
      -200,
      scrollable: scroll,
    );
    expect(
      find.text('Paste the complete private HTTPS call link.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('laptop control needs no phone bridge and keeps its own link', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [statusProbeProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AndroidVoiceScreen()),
      ),
    );
    await tester.tap(find.text('My laptop'));
    await tester.pumpAndSettle();
    expect(container.read(voiceBridgeSessionProvider), isNull);
    expect(find.text('Enable voice connection'), findsNothing);
    expect(find.text('Copy pairing details'), findsNothing);
    await tester.enterText(find.byType(TextField), 'private-laptop-link');
    await tester.tap(find.text('This phone'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('My laptop'));
    await tester.pumpAndSettle();
    expect(find.text('private-laptop-link'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Android voice starts opt-in and pairing credentials stay hidden',
    (tester) async {
      final container = ProviderContainer(
        overrides: [statusProbeProvider.overrideWith((ref) async => null)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AndroidVoiceScreen()),
        ),
      );
      expect(find.text('Enable voice connection'), findsOneWidget);
      expect(find.text('Copy pairing details'), findsNothing);
      expect(container.read(voiceBridgeSessionProvider), isNull);
      container.read(voiceBridgeSessionProvider.notifier).enable();
      await tester.pump();
      final token = container.read(voiceBridgeSessionProvider)!.token;
      expect(find.textContaining(token), findsNothing);
      expect(find.text('Copy pairing details'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unavailable Android tunnel revokes failed pairing', (
    tester,
  ) async {
    const channel = MethodChannel('buildify.ai/voice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'ok': false, 'status': 'failed'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer(
      overrides: [statusProbeProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AndroidVoiceScreen()),
      ),
    );
    await tester.tap(find.text('Enable voice connection'));
    await tester.pumpAndSettle();
    expect(container.read(voiceBridgeSessionProvider), isNull);
    expect(
      find.text('Could not start voice. Try connecting again.'),
      findsOneWidget,
    );
    expect(find.text('Enable voice connection'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
