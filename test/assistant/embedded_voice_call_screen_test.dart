import 'dart:async';
import 'dart:convert';

import 'package:buildify_flutter/screens/embedded_voice_call_screen.dart';
import 'package:buildify_flutter/services/voice_call_invitation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const microphone = MethodChannel('buildify.ai/voice-microphone');
  final invitation = Uri.parse(
    'https://test-call.trycloudflare.com/#invite=${List.filled(43, 'a').join()}',
  );
  late int verifies;
  late int creates;
  late int ends;
  late String platform;
  late Future<bool> Function() permission;
  Map<String, Object?>? nativeState;
  final channels = <MethodChannel>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    verifies = creates = ends = 0;
    platform = 'windows';
    permission = () async => true;
    nativeState = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(microphone, (_) => permission());
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        creates++;
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('buildify.ai/voice-call/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'end') ends++;
          if (call.method == 'getState') return nativeState;
          return null;
        });
        return id;
      }
      if (call.method == 'resize') {
        final args = call.arguments as Map;
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(microphone, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> run(WidgetTester tester, Future<void> Function() check) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: EmbeddedVoiceCallScreen(
              invitation: invitation,
              target: VoiceRunTarget.laptop,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await check();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      },
      () => MockClient((request) async {
        verifies++;
        expect(request.url.path, '/target');
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return http.Response(jsonEncode({'platform': platform}), 200);
      }),
    );
  }

  testWidgets('denied microphone never verifies or creates a call', (
    tester,
  ) async {
    permission = () async => false;
    await run(tester, () async {
      expect(
        find.textContaining('Microphone access is needed'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(verifies, 0);
      expect(creates, 0);
    });
  });

  testWidgets('late microphone grant after cancel cannot open a call', (
    tester,
  ) async {
    final grant = Completer<bool>();
    permission = () => grant.future;
    await run(tester, () async {
      await tester.tap(find.text('End call'));
      await tester.pump();
      grant.complete(true);
      await tester.pump();
      expect(verifies, 0);
      expect(creates, 0);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('wrong target cannot create a native call', (tester) async {
    platform = 'android';
    await run(tester, () async {
      expect(verifies, 1);
      expect(creates, 0);
      expect(find.textContaining('Could not open the call'), findsOneWidget);
    });
  });

  testWidgets('recovers page-ready state emitted before the channel attached', (
    tester,
  ) async {
    nativeState = {'ready': true, 'ended': false};
    await run(tester, () async {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(AndroidView), findsOneWidget);
    });
  });

  testWidgets(
    'unavailable native WebView offers retry instead of a broken view',
    (tester) async {
      nativeState = {'error': 'webview_unavailable'};
      await run(tester, () async {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(AndroidView), findsNothing);
        expect(
          find.textContaining('Update Android System WebView'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      });
    },
  );

  testWidgets('verified call stays in-app and end disposes native media', (
    tester,
  ) async {
    await run(tester, () async {
      await tester.pump(const Duration(milliseconds: 100));
      expect(verifies, 1);
      expect(creates, 1);
      expect(find.byType(AndroidView), findsOneWidget);
      expect(find.text('Runs on your paired laptop'), findsOneWidget);
      await tester.tap(find.text('End call'));
      await tester.pump();
      expect(find.byType(AndroidView), findsNothing);
      expect(ends, greaterThanOrEqualTo(1));
    });
  });

  testWidgets('background ends the call and retry re-verifies the target', (
    tester,
  ) async {
    await run(tester, () async {
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(AndroidView), findsNothing);
      expect(ends, greaterThanOrEqualTo(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(verifies, 2);
      expect(creates, 2);
    });
  });
}
