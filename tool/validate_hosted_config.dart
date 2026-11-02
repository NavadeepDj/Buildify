import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/services/hosted_auth_config.dart';

void main(List<String> args) {
  try {
    if (args.isEmpty || args.length > 2) {
      throw const FormatException(
        'Usage: dart tool/validate_hosted_config.dart <config.json> [development|staging|production]',
      );
    }
    final data = jsonDecode(File(args.first).readAsStringSync());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Configuration must be a JSON object.');
    }
    const allowed = {
      'BUILDIFY_ENV',
      'SUPABASE_URL',
      'SUPABASE_PUBLISHABLE_KEY',
      'GITHUB_CLIENT_ID',
    };
    if (data.keys.any((key) => !allowed.contains(key)) ||
        data.values.any((value) => value is! String)) {
      throw const FormatException(
        'Only documented public string values are allowed in a Flutter configuration file.',
      );
    }
    final expectedEnvironment = args.length == 2 ? args[1] : 'development';
    if (data['BUILDIFY_ENV'] != expectedEnvironment) {
      throw const FormatException(
        'The configuration environment does not match the requested target.',
      );
    }
    final config = HostedAuthConfig.parse(
      environment: data['BUILDIFY_ENV'] as String? ?? '',
      url: data['SUPABASE_URL'] as String? ?? '',
      publishableKey: data['SUPABASE_PUBLISHABLE_KEY'] as String? ?? '',
    );
    if (config == null) {
      throw const FormatException(
        'The project URL and public key are required.',
      );
    }
    stdout.writeln(
      'Public hosted configuration validated for $expectedEnvironment.',
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } catch (_) {
    stderr.writeln(
      'Could not read the configuration file. No values were printed.',
    );
    exitCode = 1;
  }
}
