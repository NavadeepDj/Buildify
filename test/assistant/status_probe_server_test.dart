import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/assistant/status_probe_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'synthetic-status-probe-token-for-testing';
  late StatusProbeServer server;
  late HttpClient client;
  var inspections = 0;
  var state = 'stopped';
  var observed = true;
  var plansRequested = 0;

  setUp(() async {
    inspections = 0;
    state = 'stopped';
    observed = true;
    plansRequested = 0;
    client = HttpClient();
    server = await StatusProbeServer.start(
      token: token,
      port: 0,
      requestSetup: () {
        plansRequested++;
        return {'state': 'needs_approval'};
      },
      setupStatus: () => {'state': 'needs_approval', 'health_verified': false},
      inspect: () async {
        inspections++;
        return {
          'server': {
            'status': observed ? 'observed' : 'failed',
            'value': {'state': state},
          },
        };
      },
    );
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<(int, Map<String, dynamic>)> get(
    String path, {
    String? credential,
  }) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (credential != null) {
      request.headers.set('Authorization', 'Bearer $credential');
    }
    final response = await request.close();
    return (
      response.statusCode,
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>,
    );
  }

  test('rejects unauthorized requests before reading runtime', () async {
    expect((await get('/v1/status')).$1, 401);
    expect((await get('/v1/status', credential: 'wrong')).$1, 401);
    expect(inspections, 0);
  });
  test(
    'returns an observed state without claiming inference verification',
    () async {
      final (code, result) = await get('/v1/status', credential: token);
      expect(code, 200);
      expect(result['model_state'], 'stopped');
      expect(result['health_verified'], false);
      expect(result['source'], 'buildify_live_app');
      expect(DateTime.tryParse(result['observed_at'] as String), isNotNull);
      state = 'running';
      final running = (await get('/v1/status', credential: token)).$2;
      expect(running['model_state'], 'running');
      expect(running['health_verified'], false);
    },
  );
  test('unavailable observations remain unknown', () async {
    observed = false;
    state = 'running';
    expect(
      (await get('/v1/status', credential: token)).$2['model_state'],
      'unknown',
    );
  });
  test('rejects parameters and arbitrary routes without inspection', () async {
    expect((await get('/v1/status?command=start', credential: token)).$1, 400);
    expect((await get('/start', credential: token)).$1, 400);
    expect(inspections, 0);
  });
  test(
    'setup requires authentication and refuses remote approval arguments',
    () async {
      Future<int> post(String body, {bool authorized = true}) async {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/v1/setup-plan'),
        );
        if (authorized) request.headers.set('Authorization', 'Bearer $token');
        request.write(body);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await post('{}', authorized: false), 401);
      expect(await post('{"approved":true}'), 400);
      expect(plansRequested, 0);
      expect(await post('{}'), 200);
      expect(plansRequested, 1);
      final status = await get('/v1/setup-status', credential: token);
      expect(status.$2['state'], 'needs_approval');
      expect(status.$2['health_verified'], false);
    },
  );
}
