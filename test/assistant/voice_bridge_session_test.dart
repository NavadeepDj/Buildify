import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/assistant/voice_bridge_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EphemeralPortSession extends VoiceBridgeSessionController {
  _EphemeralPortSession(super.ref) {
    state = VoiceBridgeSession(
      token: VoiceBridgeSession.create().token,
      port: 0,
    );
  }
}

void main() {
  test('pairing tokens are unique, URL safe, and contain 256 random bits', () {
    final first = VoiceBridgeSession.create();
    final second = VoiceBridgeSession.create();
    expect(first.token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(base64Url.decode('${first.token}='), hasLength(32));
    expect(first.token, isNot(second.token));
    expect(first.port, 18791);
  });

  test('voice pairing starts disabled and reuses the active session', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(voiceBridgeSessionProvider.notifier);
    expect(container.read(voiceBridgeSessionProvider), isNull);
    await controller.disable();
    final first = controller.enable();
    expect(identical(first, controller.enable()), isTrue);
  });

  test(
    'runtime pairing authenticates tools and disconnect closes the bridge',
    () async {
      // Create the real loopback client before provider initialization can
      // install Flutter's widget-test HTTP override.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final container = ProviderContainer(
        overrides: [
          voiceBridgeSessionProvider.overrideWith(
            (ref) => _EphemeralPortSession(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(voiceBridgeSessionProvider.notifier);
      final pairing = controller.enable();
      final server = await container.read(statusProbeProvider.future);
      expect(server, isNotNull);
      final uri = Uri.parse('http://127.0.0.1:${server!.port}/v1/tools');

      final unauthorized = await (await client.getUrl(uri)).close();
      await unauthorized.drain<void>();
      expect(unauthorized.statusCode, 401);

      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer ${pairing.token}');
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect(response.statusCode, 200);
      expect(body['tools'], isNotEmpty);

      await controller.disable();
      expect(container.read(voiceBridgeSessionProvider), isNull);
      // Explicit close and provider disposal can overlap during disconnect.
      await server.close();
      final next = controller.enable();
      expect(next.token, isNot(pairing.token));
    },
  );
}
