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
          client: MockClient((r) async => response),
        );
        await expectLater(
          v.verify(port: 8080),
          throwsA(isA<ModelOperationFailure>()),
        );
      }
    },
  );
  test('invalid port cannot contact a service', () async {
    final v = ModelEndpointVerifier(
      client: MockClient((r) async => throw StateError('No request expected')),
    );
    await expectLater(v.verify(port: 0), throwsA(isA<ModelOperationFailure>()));
  });
}
