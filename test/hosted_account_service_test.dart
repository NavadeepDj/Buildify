import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:buildify_flutter/services/hosted_account_service.dart';

class MemoryPkceStorage extends sb.GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  final user = <String, dynamic>{
    'id': '11111111-1111-4111-8111-111111111111',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'test@example.com',
    'email_confirmed_at': '2026-10-28T00:00:00Z',
    'created_at': '2026-10-28T00:00:00Z',
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': {'display_name': 'Test User'},
  };
  Map<String, dynamic> session() => {
    'access_token': 'test-access-token',
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': user,
  };
  HostedAccountService service(http.Response Function(http.Request) handler) {
    final client = sb.SupabaseClient(
      'https://test-project.supabase.co',
      'sb_publishable_test_fixture',
      authOptions: sb.AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: MemoryPkceStorage(),
      ),
      httpClient: MockClient((request) async => handler(request)),
    );
    addTearDown(client.dispose);
    return HostedAccountService(client);
  }

  http.Response response(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {
      'content-type': 'application/json',
      'x-supabase-api-version': '2024-01-01',
    },
  );

  test('unconfigured service never checks a local password', () async {
    final auth = HostedAccountService(null);
    expect(auth.isConfigured, false);
    await expectLater(
      auth.signIn(email: 'test@example.com', password: 'password123'),
      throwsA(isA<AccountFailure>()),
    );
    expect(await auth.accountChanges.first, isNull);
  });
  test('signup normalizes email and uses the cloud auth endpoint', () async {
    final auth = service((request) {
      expect(request.url.path, '/auth/v1/signup');
      final body = jsonDecode(request.body) as Map;
      expect(body['email'], 'test@example.com');
      expect(body['data']['display_name'], 'Test User');
      return response({...user, 'email_confirmed_at': null});
    });
    final result = await auth.signUp(
      name: ' Test User ',
      email: ' TEST@example.com ',
      password: 'password123',
    );
    expect(result.needsVerification, true);
    expect(auth.currentAccount, isNull);
  });
  test(
    'unconfirmed login directs to verification without a signed-in account',
    () async {
      final auth = service(
        (_) => response({
          'code': 'email_not_confirmed',
          'msg': 'Email not confirmed',
        }, 400),
      );
      expect(
        (await auth.signIn(
          email: 'test@example.com',
          password: 'password123',
        )).needsVerification,
        true,
      );
      expect(auth.currentAccount, isNull);
    },
  );
  test(
    'invalid credentials are actionable and provider details are redacted',
    () async {
      final auth = service(
        (_) => response({
          'code': 'invalid_credentials',
          'msg': 'private-provider-details',
        }, 400),
      );
      await expectLater(
        auth.signIn(email: 'test@example.com', password: 'wrong'),
        throwsA(
          isA<AccountFailure>()
              .having(
                (e) => e.message,
                'message',
                contains('Email or password is incorrect'),
              )
              .having(
                (e) => e.message,
                'redaction',
                isNot(contains('private-provider-details')),
              ),
        ),
      );
    },
  );
  test(
    'SMTP restrictions and rate limits are not presented as email success',
    () async {
      for (final code in [
        'email_address_not_authorized',
        'over_email_send_rate_limit',
      ]) {
        final auth = service(
          (_) => response({'code': code, 'msg': 'provider details'}, 422),
        );
        await expectLater(
          auth.signUp(
            name: 'Test',
            email: 'test@example.com',
            password: 'password123',
          ),
          throwsA(isA<AccountFailure>()),
        );
      }
    },
  );
  test(
    'verification uses the email code and establishes confirmed identity',
    () async {
      final auth = service((request) {
        expect(request.url.path, '/auth/v1/verify');
        final body = jsonDecode(request.body) as Map;
        expect(body['email'], 'test@example.com');
        expect(body['token'], '123456');
        expect(body['type'], 'email');
        return response(session());
      });
      await auth.verifyEmail(email: ' TEST@example.com ', code: '123456');
      expect(auth.currentAccount?.id, user['id']);
      expect(auth.currentAccount?.name, 'Test User');
    },
  );
  test('invalid code is rejected before any network call', () async {
    final auth = service((_) {
      fail('Invalid input must not contact the provider');
    });
    await expectLater(
      auth.verifyEmail(email: 'test@example.com', code: 'not-a-code'),
      throwsA(isA<AccountFailure>()),
    );
  });
  test(
    'resend uses signup email type and logout clears current identity',
    () async {
      final paths = <String>[];
      final auth = service((request) {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/token')) return response(session());
        if (request.url.path.endsWith('/resend')) {
          expect((jsonDecode(request.body) as Map)['type'], 'signup');
        }
        return response({});
      });
      await auth.signIn(email: 'test@example.com', password: 'password123');
      expect(auth.currentAccount, isNotNull);
      await auth.resendVerification('test@example.com');
      await auth.signOut();
      expect(auth.currentAccount, isNull);
      expect(
        paths,
        containsAll(['/auth/v1/token', '/auth/v1/resend', '/auth/v1/logout']),
      );
    },
  );
}
