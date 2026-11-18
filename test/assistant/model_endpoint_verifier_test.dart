import 'dart:async';
import 'dart:convert';
import 'package:buildify_flutter/assistant/model_endpoint_verifier.dart';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'verifies actual text and sends credentials only to local endpoint',
    () async {
      final v = ModelEndpointVerifier(
        client: MockClient((r) async {
          expect(r.url.host, '127.0.0.1');
          expect(r.followRedirects, isFalse);
          expect(r.headers['Authorization'], 'Bearer test-key');
          if (r.method == 'GET') {
            expect(r.url.path, '/health');
            return http.Response('{"status":"ok"}', 200);
          }
          final body = jsonDecode(r.body) as Map;
          expect(body['max_tokens'], 16);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Hello'},
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(await v.verify(port: 8080, apiKey: 'test-key'), isA<Duration>());
    },
  );
  test(
    'rejects redirects, empty output, malformed JSON and oversized response',
    () async {
      for (final response in [
        http.Response('redirect', 302),
        http.Response('{}', 200),
        http.Response('not json', 200),
        http.Response(List.filled(65537, 'x').join(), 200),
        http.Response('{"choices":[{"message":{"content":" "}}]}', 200),
      ]) {
        final v = ModelEndpointVerifier(
          client: MockClient(
            (r) async =>
                r.method == 'GET'
                    ? http.Response('{"status":"ok"}', 200)
                    : response,
          ),
        );
        await expectLater(
          v.verify(port: 8080),
          throwsA(isA<ModelOperationFailure>()),
        );
      }
    },
  );
  test('waits for cold listener and model load before one inference', () async {
    var healthRequests = 0;
    var inferenceRequests = 0;
    final verifier = ModelEndpointVerifier(
      readinessRetryInterval: const Duration(milliseconds: 1),
      client: MockClient((request) async {
        expect(request.url.host, '127.0.0.1');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer local-key');
        if (request.method == 'GET') {
          healthRequests++;
          if (healthRequests == 1) {
            throw http.ClientException('listener loading');
          }
          return http.Response('{}', healthRequests < 4 ? 503 : 200);
        }
        inferenceRequests++;
        return http.Response(
          '{"choices":[{"message":{"content":"Hello"}}]}',
          200,
        );
      }),
    );
    await verifier.verify(port: 8080, apiKey: 'local-key');
    expect(healthRequests, 4);
    expect(inferenceRequests, 1);
  });

  test('readiness times out without sending inference', () async {
    var requests = 0;
    final verifier = ModelEndpointVerifier(
      readinessTimeout: const Duration(milliseconds: 15),
      readinessRetryInterval: const Duration(milliseconds: 1),
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        return http.Response('{}', 503);
      }),
    );
    await expectLater(
      verifier.verify(port: 8080),
      throwsA(isA<ModelOperationFailure>()),
    );
    expect(requests, greaterThan(0));
  });

  test(
    'does not follow health redirects or retry authentication errors',
    () async {
      for (final status in [302, 401, 403, 500]) {
        var requests = 0;
        final verifier = ModelEndpointVerifier(
          client: MockClient((request) async {
            requests++;
            expect(request.method, 'GET');
            expect(request.followRedirects, isFalse);
            return http.Response(
              '',
              status,
              headers: {'location': 'https://example.com'},
            );
          }),
        );
        await expectLater(
          verifier.verify(port: 8080),
          throwsA(isA<ModelOperationFailure>()),
        );
        expect(requests, 1);
      }
    },
  );
  test('invalid port cannot contact a service', () async {
    final v = ModelEndpointVerifier(
      client: MockClient((r) async => throw StateError('No request expected')),
    );
    await expectLater(v.verify(port: 0), throwsA(isA<ModelOperationFailure>()));
  });

  test(
    'closing a cold-start verifier interrupts readiness before inference',
    () async {
      final healthStarted = Completer<void>();
      final healthResponse = Completer<http.Response>();
      var inferenceRequests = 0;
      final verifier = ModelEndpointVerifier(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            healthStarted.complete();
            return healthResponse.future;
          }
          inferenceRequests++;
          return http.Response('{}', 200);
        }),
      );
      final outcome = expectLater(
        verifier.verify(port: 8080),
        throwsA(isA<ModelOperationFailure>()),
      );
      await healthStarted.future;
      verifier.close();
      await outcome.timeout(const Duration(seconds: 1));
      healthResponse.complete(http.Response('{}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(inferenceRequests, 0);
    },
  );
}
