import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:buildify_flutter/services/hosted_auth_config.dart';

void main() {
  HostedAuthConfig? parse(
    String key, {
    String url = 'https://test-project.supabase.co',
    String environment = 'development',
  }) => HostedAuthConfig.parse(
    environment: environment,
    url: url,
    publishableKey: key,
  );

  test('no configured backend remains an explicit local-only build', () {
    expect(
      HostedAuthConfig.parse(
        environment: 'development',
        url: '',
        publishableKey: '',
      ),
      isNull,
    );
  });
  test('accepts public publishable and legacy anon keys', () {
    expect(parse('sb_publishable_test_fixture')?.environment, 'development');
    final payload = base64Url.encode(utf8.encode(jsonEncode({'role': 'anon'})));
    expect(parse('header.$payload.signature'), isNotNull);
  });
  test('rejects server credentials without reflecting their value', () {
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'role': 'service_role'})),
    );
    for (final key in [
      'sb_secret_private_fixture',
      'header.$payload.signature',
      'sb_publishable_REPLACE_ME',
      '',
      'malformed',
    ]) {
      expect(
        () => parse(key),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message.contains(key) && key.isNotEmpty,
            'does not echo the key',
            false,
          ),
        ),
      );
    }
  });
  test('rejects unsafe origins and unknown environments', () {
    for (final url in [
      'http://test.supabase.co',
      'https://user:password@test.supabase.co',
      'https://test.supabase.co/path',
      'https://test.supabase.co?token=secret',
      'not-a-url',
    ]) {
      expect(
        () => parse('sb_publishable_test_fixture', url: url),
        throwsFormatException,
      );
    }
    expect(
      () => parse('sb_publishable_test_fixture', environment: 'prod'),
      throwsFormatException,
    );
  });
}
