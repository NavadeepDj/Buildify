import 'dart:convert';
import 'package:buildify_flutter/assistant/cloud_intent.dart';
import 'package:buildify_flutter/services/management_account_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../helpers/management_fixtures.dart';

void main() {
  final valid = {
    'status': 'ready',
    'task': 'short_answers',
    'preference': 'speed',
    'scope': 'device_network',
    'reply': 'Prepare a local plan.',
  };
  const messages = [IntentMessage('user', 'Fast answers on my laptop')];
  http.Response response(Map<String, Object> data) => http.Response(
    jsonEncode({'data': data, 'request_id': requestId}),
    200,
    headers: {'content-type': 'application/json', 'x-request-id': requestId},
  );
  test(
    'only conversation and session credentials sent to fixed management route',
    () async {
      final service = CloudIntentService(
        config,
        FakeSessions(),
        clientFactory:
            () => MockClient((request) async {
              expect(
                request.url.toString(),
                '${config.baseUri}/v1/assistant/intent',
              );
              expect(request.followRedirects, false);
              expect(jsonDecode(request.body), {
                'messages': [
                  {'role': 'user', 'text': messages.first.text},
                ],
              });
              expect(
                request.headers['Authorization'],
                'Bearer ${credentials.accessToken}',
              );
              return response(valid);
            }),
      );
      expect((await service.interpret(messages)).canPrepare, true);
    },
  );
  test('rejects extra executable fields and public-ready responses', () {
    for (final value in [
      {...valid, 'approval': true},
      {...valid, 'scope': 'public'},
      {...valid, 'task': 'shell'},
    ]) {
      expect(() => CloudIntent.parse(value), throwsA(isA<IntentFailure>()));
    }
  });
  test('no request without session or with oversized conversation', () async {
    final sessions = FakeSessions()..current = null;
    final service = CloudIntentService(
      config,
      sessions,
      clientFactory: () => MockClient((_) async => fail('No HTTP expected')),
    );
    await expectLater(
      service.interpret(messages),
      throwsA(isA<IntentFailure>()),
    );
    await expectLater(
      service.interpret([IntentMessage('user', 'x' * 1501)]),
      throwsA(isA<IntentFailure>()),
    );
  });
  test(
    'account switching discards result and upstream errors are not surfaced',
    () async {
      final sessions = FakeSessions();
      final service = CloudIntentService(
        config,
        sessions,
        clientFactory:
            () => MockClient((_) async {
              sessions.current = const ManagementSession(
                userId: userB,
                accessToken: 'other',
              );
              return response(valid);
            }),
      );
      await expectLater(
        service.interpret(messages),
        throwsA(isA<IntentFailure>()),
      );
    },
  );
  test('401 refreshes once; 503 does not retry billed request', () async {
    for (final status in [401, 503]) {
      var calls = 0;
      final sessions = FakeSessions()..refreshed = credentials;
      final service = CloudIntentService(
        config,
        sessions,
        clientFactory:
            () => MockClient((_) async {
              calls++;
              return calls == 1
                  ? http.Response('provider-secret', status)
                  : response(valid);
            }),
      );
      if (status == 401) {
        expect((await service.interpret(messages)).canPrepare, true);
        expect(calls, 2);
      } else {
        await expectLater(
          service.interpret(messages),
          throwsA(isA<IntentFailure>()),
        );
        expect(calls, 1);
      }
    }
  });
}
