import 'dart:convert';

/// Public build configuration only. Never put a server key in a Flutter build.
class HostedAuthConfig {
  const HostedAuthConfig({
    required this.environment,
    required this.url,
    required this.publishableKey,
  });

  final String environment;
  final String url;
  final String publishableKey;

  static HostedAuthConfig? fromDefines() => parse(
    environment: const String.fromEnvironment(
      'BUILDIFY_ENV',
      defaultValue: 'development',
    ),
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  static HostedAuthConfig? parse({
    required String environment,
    required String url,
    required String publishableKey,
  }) {
    if (url.isEmpty && publishableKey.isEmpty) return null;
    if (!{'development', 'staging', 'production'}.contains(environment)) {
      throw const FormatException(
        'BUILDIFY_ENV must be development, staging, or production.',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'SUPABASE_URL must be an HTTPS project origin.',
      );
    }
    var publicKey =
        publishableKey.startsWith('sb_publishable_') &&
        publishableKey.length > 'sb_publishable_'.length;
    if (!publicKey) {
      try {
        final parts = publishableKey.split('.');
        if (parts.length == 3) {
          final claims = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          );
          publicKey = claims is Map && claims['role'] == 'anon';
        }
      } catch (_) {
        publicKey = false;
      }
    }
    if (!publicKey ||
        publishableKey.contains('REPLACE') ||
        publishableKey.contains(RegExp(r'\s'))) {
      throw const FormatException(
        'SUPABASE_PUBLISHABLE_KEY must be a public publishable or legacy anon key. Server keys are not allowed.',
      );
    }
    return HostedAuthConfig(
      environment: environment,
      url: uri.origin,
      publishableKey: publishableKey,
    );
  }
}
