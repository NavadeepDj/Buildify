// Explicit native-runtime smoke; skipped by default and never enabled in CI.
import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/services/desktop_server_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled =
      Platform.isWindows && Platform.environment['HOSTANY_WINDOWS_LIVE'] == '1';
  test(
    'Windows CPU inference, authenticated endpoint and public tunnel',
    () async {
      final model = Platform.environment['HOSTANY_SMOKE_MODEL'];
      expect(model, isNotNull);
      expect(File(model!).existsSync(), true);
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final bridge = DesktopServerBridge();
      final chatModel = Platform.environment['HOSTANY_CHAT_SMOKE'] == '1';
      const key = 'synthetic-windows-smoke-only';
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 10);
      Future<(int, String)> completion(
        String base, {
        bool authenticated = true,
      }) async {
        final request = await client.postUrl(
          Uri.parse(
            '$base${chatModel ? '/v1/chat/completions' : '/completion'}',
          ),
        );
        request.headers.contentType = ContentType.json;
        if (authenticated) request.headers.set('Authorization', 'Bearer $key');
        request.write(
          jsonEncode(
            chatModel
                ? {
                  'model': 'local',
                  'messages': [
                    {'role': 'user', 'content': 'Say hello.'},
                  ],
                  'max_tokens': 8,
                  'temperature': 0,
                }
                : {
                  'prompt': 'Once upon a time',
                  'n_predict': 8,
                  'temperature': 0,
                },
          ),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 40),
        );
        return (
          response.statusCode,
          await response.transform(utf8.decoder).join(),
        );
      }

      String generated(String body) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return chatModel
            ? ((data['choices'] as List).first as Map)['message']['content']
                as String
            : data['content'] as String;
      }

      try {
        final start = await bridge.startServer(
          modelPath: model,
          port: port,
          apiKey: key,
        );
        expect(start.ok, true, reason: start.message);
        var ready = false;
        for (var i = 0; i < 60; i++) {
          final status = await bridge.getServerStatus();
          if (status?.status == 'running') {
            ready = true;
            break;
          }
          expect(status?.status, 'starting', reason: status?.lastError);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(ready, true);
        final denied = await completion(
          'http://127.0.0.1:$port',
          authenticated: false,
        );
        expect(denied.$1, 401);
        final local = await completion('http://127.0.0.1:$port');
        expect(local.$1, 200);
        expect(generated(local.$2), isNotEmpty);

        expect((await bridge.startTunnel(port: port)).ok, true);
        String? url;
        for (var i = 0; i < 90; i++) {
          final status = await bridge.getTunnelStatus();
          if (status?.status == 'running' && status?.publicUrl != null) {
            url = status!.publicUrl;
            break;
          }
          expect(status?.status, isNot('failed'), reason: status?.lastError);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          url,
          isNotNull,
          reason: (await bridge.getTunnelStatus())?.lastError,
        );
        // Wait for the quick-tunnel DNS/edge route to propagate, without printing it.
        (int, String)? public;
        for (var i = 0; i < 12; i++) {
          try {
            public = await completion(url!);
            if (public.$1 == 200) break;
          } catch (_) {
            /* Propagating. */
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        expect(public?.$1, 200);
        expect(generated(public!.$2), isNotEmpty);
        expect((await completion(url!, authenticated: false)).$1, 401);
      } finally {
        client.close(force: true);
        expect((await bridge.stopTunnel()).ok, true);
        expect((await bridge.stopServer()).ok, true);
      }
      // Stopping must really release the native process's listening socket.
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      await rebound.close();
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
