import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/services/hosted_auth_config.dart';

/// Read-only checks. Never print keys, response rows, or account information.
Future<void> main(List<String> args) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final data =
        jsonDecode(
              File(
                args.isEmpty ? 'config/supabase.development.json' : args.single,
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final config = HostedAuthConfig.parse(
      environment: data['BUILDIFY_ENV'] as String,
      url: data['SUPABASE_URL'] as String,
      publishableKey: data['SUPABASE_PUBLISHABLE_KEY'] as String,
    );
    if (config == null) {
      throw const FormatException('Public project configuration is required.');
    }
    for (final path in [
      '/auth/v1/settings',
      '/rest/v1/profiles?select=id&limit=1',
    ]) {
      final request = await client
          .getUrl(Uri.parse('${config.url}$path'))
          .timeout(const Duration(seconds: 20));
      request.headers.set('apikey', config.publishableKey);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = jsonDecode(
        await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 20)),
      );
      if (path.startsWith('/auth/')) {
        if (response.statusCode != 200 || body is! Map) {
          stdout.writeln('Auth settings: HTTP ${response.statusCode}.');
          exitCode = 1;
        } else {
          final external = body['external'];
          stdout.writeln(
            'Auth reachable: email=${external is Map ? external['email'] : null}; auto-confirm=${body['mailer_autoconfirm']}.',
          );
          if (external is! Map ||
              external['email'] != true ||
              body['mailer_autoconfirm'] != false) {
            exitCode = 1;
          }
        }
      } else if (response.statusCode == 404) {
        stdout.writeln(
          'Profiles: unavailable (HTTP 404, code=${body is Map ? body['code'] : null}). Apply/check the profile migration and schema cache.',
        );
        exitCode = 1;
      } else if ({401, 403}.contains(response.statusCode) &&
          body is Map &&
          body['code'] == '42501') {
        stdout.writeln(
          'Profiles: anonymous access denied as expected. Owner and second-account tests are still required.',
        );
      } else {
        stdout.writeln(
          'Profiles: unexpected HTTP ${response.statusCode}; code=${body is Map ? body['code'] : null}. Review access policies; response rows were not printed.',
        );
        exitCode = 1;
      }
    }
  } catch (_) {
    stderr.writeln(
      'Backend check could not complete. Check configuration, DNS, and network access. No configuration values were printed.',
    );
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}
