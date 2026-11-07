import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:buildify_flutter/services/management_account_service.dart';
import 'package:buildify_flutter/services/hosted_auth_config.dart';
import 'package:buildify_flutter/services/management_api_config.dart';
import 'helpers/management_fixtures.dart';

class TrackedClient extends MockClient {
  TrackedClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.Response success({
  String id = userA,
  String name = 'Server profile',
  String headerId = requestId,
  Map<String, dynamic>? extra,
}) => http.Response(
  jsonEncode({
    'data': {'id': id, 'display_name': name, ...?extra},
    'request_id': requestId,
  }),
  200,
  headers: {'content-type': 'application/json', 'x-request-id': headerId},
);

void main() {
  test(
    'Dart consumer accepts the shared OpenAPI-validated account fixture',
    () async {
      final body =
          File('contracts/management/examples/account.json').readAsStringSync();
      final example = jsonDecode(body) as Map;
      final service = ManagementAccountService(
        config: config,
        sessions: FakeSessions(),
        clientFactory:
            () => MockClient(
              (_) async => http.Response(
                body,
                200,
                headers: {
                  'content-type': 'application/json',
                  'x-request-id': example['request_id'] as String,
                },
              ),
            ),
      );
      expect((await service.fetchAccount()).displayName, 'Example user');
    },
  );
  test(
    'configuration is optional and cannot redirect a user token to another project',
    () {
      expect(ManagementApiConfig.parse('', null), isNull);
      final auth = HostedAuthConfig.parse(
        environment: 'development',
        url: 'https://test-project.supabase.co',
        publishableKey: 'sb_publishable_fixture',
      );
      for (final url in [
        'http://test-project.supabase.co/functions/v1/management',
        'https://other-project.supabase.co/functions/v1/management',
        'https://test-project.supabase.co/functions/v1/management?token=private',
        'https://user:private@test-project.supabase.co/functions/v1/management',
        'https://test-project.supabase.co/other',
      ]) {
        expect(
          () => ManagementApiConfig.parse(url, auth),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'request uses session bearer/public key and the fixed contract route without selectors or redirects',
    () async {
      final source = FakeSessions();
      late TrackedClient client;
      final service = ManagementAccountService(
        config: config,
        sessions: source,
        clientFactory:
            () =>
                client = TrackedClient((request) async {
                  expect(
                    request.url.toString(),
                    '${config.baseUri}/v1/account',
                  );
                  expect(request.method, 'GET');
                  expect(
                    request.headers['Authorization'],
                    'Bearer synthetic-first',
                  );
                  expect(request.headers['apikey'], 'sb_publishable_fixture');
                  expect(request.body, isEmpty);
                  expect(request.followRedirects, false);
                  return success();
                }),
      );
      expect((await service.fetchAccount()).displayName, 'Server profile');
      expect(client.closed, true);
      expect(credentials.toString(), isNot(contains(credentials.accessToken)));
    },
  );

  test(
    '401 refreshes once, retries with the new token, and closes each request client',
    () async {
      final source =
          FakeSessions()
            ..refreshed = const ManagementSession(
              userId: userA,
              accessToken: 'synthetic-refreshed',
            );
      final clients = <TrackedClient>[];
      final service = ManagementAccountService(
        config: config,
        sessions: source,
        clientFactory: () {
          final index = clients.length;
          final client = TrackedClient((request) async {
            expect(
              request.headers['Authorization'],
              index == 0
                  ? 'Bearer synthetic-first'
                  : 'Bearer synthetic-refreshed',
            );
            return index == 0
                ? http.Response('Gateway rejection', 401)
                : success();
          });
          clients.add(client);
          return client;
        },
      );
      expect((await service.fetchAccount()).id, userA);
      expect(source.reads, [false, true]);
      expect(clients.every((client) => client.closed), true);
    },
  );

  test(
    'repeated 401 stops after one refresh; missing session never contacts the API',
    () async {
      final source = FakeSessions();
      var calls = 0;
      final service = ManagementAccountService(
        config: config,
        sessions: source,
        clientFactory:
            () => MockClient((_) async {
              calls++;
              return http.Response('private-provider-detail', 401);
            }),
      );
      await expectLater(
        service.fetchAccount(),
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.kind,
            'kind',
            ManagementFailureKind.signInRequired,
          ),
        ),
      );
      expect(calls, 2);
      source.current = null;
      await expectLater(
        service.fetchAccount(),
        throwsA(isA<ManagementFailure>()),
      );
      expect(calls, 2);
    },
  );

  test(
    'rate limits and unavailable/non-JSON provider errors never trigger a refresh or leak details',
    () async {
      for (final status in [403, 429, 503, 302]) {
        final source = FakeSessions();
        final service = ManagementAccountService(
          config: config,
          sessions: source,
          clientFactory:
              () => MockClient(
                (_) async => http.Response(
                  'private provider detail',
                  status,
                  headers: {
                    'retry-after': '7',
                    'location': 'https://untrusted.example',
                  },
                ),
              ),
        );
        await expectLater(
          service.fetchAccount(),
          throwsA(
            isA<ManagementFailure>()
                .having(
                  (e) => e.toString(),
                  'safe message',
                  isNot(contains('private provider detail')),
                )
                .having(
                  (e) => e.retryAfterSeconds,
                  'retry delay',
                  status == 429 ? 7 : null,
                ),
          ),
        );
        expect(source.reads, [false]);
      }
    },
  );

  test(
    'confirmation rejection is actionable and malformed retry headers get a safe cooldown',
    () async {
      final confirmation = ManagementAccountService(
        config: config,
        sessions: FakeSessions(),
        clientFactory:
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'error': {'code': 'email_confirmation_required'},
                }),
                403,
                headers: {'content-type': 'application/json'},
              ),
            ),
      );
      await expectLater(
        confirmation.fetchAccount(),
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.kind,
            'kind',
            ManagementFailureKind.confirmationRequired,
          ),
        ),
      );
      final limited = ManagementAccountService(
        config: config,
        sessions: FakeSessions(),
        clientFactory:
            () => MockClient(
              (_) async =>
                  http.Response('', 429, headers: {'retry-after': '-1'}),
            ),
      );
      await expectLater(
        limited.fetchAccount(),
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.retryAfterSeconds,
            'cooldown',
            60,
          ),
        ),
      );
    },
  );

  test(
    'foreign identity, malformed schema, unapproved fields and mismatched request IDs are rejected',
    () async {
      for (final reply in [
        success(id: userB),
        success(name: ' '),
        success(name: 'a' * 81),
        success(headerId: userB),
        success(extra: {'is_pro': true}),
        http.Response('<html>not JSON</html>', 200),
      ]) {
        final service = ManagementAccountService(
          config: config,
          sessions: FakeSessions(),
          clientFactory: () => MockClient((_) async => reply),
        );
        await expectLater(
          service.fetchAccount(),
          throwsA(
            isA<ManagementFailure>().having(
              (e) => e.kind,
              'kind',
              ManagementFailureKind.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test(
    'signout while a read is pending cannot return the old account',
    () async {
      final source = FakeSessions();
      final pending = Completer<http.Response>();
      final sent = Completer<void>();
      final service = ManagementAccountService(
        config: config,
        sessions: source,
        clientFactory:
            () => MockClient((_) {
              sent.complete();
              return pending.future;
            }),
      );
      final result = service.fetchAccount();
      await sent.future;
      source.current = null;
      pending.complete(success());
      await expectLater(
        result,
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.kind,
            'kind',
            ManagementFailureKind.signInRequired,
          ),
        ),
      );
    },
  );

  test(
    'account switch during refresh never retries the old operation as a different account',
    () async {
      final source =
          FakeSessions()
            ..refreshed = const ManagementSession(
              userId: userB,
              accessToken: 'synthetic-other',
            );
      var calls = 0;
      final service = ManagementAccountService(
        config: config,
        sessions: source,
        clientFactory:
            () => MockClient((_) async {
              calls++;
              return http.Response('', 401);
            }),
      );
      await expectLater(
        service.fetchAccount(),
        throwsA(isA<ManagementFailure>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'oversized streamed responses and stalled requests are bounded and clients close',
    () async {
      final large = ManagementAccountService(
        config: config,
        sessions: FakeSessions(),
        clientFactory:
            () => MockClient.streaming(
              (_, _) async => http.StreamedResponse(
                Stream.value(List.filled(65537, 0)),
                200,
              ),
            ),
      );
      await expectLater(
        large.fetchAccount(),
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.kind,
            'kind',
            ManagementFailureKind.invalidResponse,
          ),
        ),
      );
      final pending = Completer<http.Response>();
      late TrackedClient client;
      final stalled = ManagementAccountService(
        config: config,
        sessions: FakeSessions(),
        timeout: const Duration(milliseconds: 15),
        clientFactory: () => client = TrackedClient((_) => pending.future),
      );
      await expectLater(
        stalled.fetchAccount(),
        throwsA(
          isA<ManagementFailure>().having(
            (e) => e.kind,
            'kind',
            ManagementFailureKind.unavailable,
          ),
        ),
      );
      expect(client.closed, true);
      pending.complete(success());
    },
  );
}
