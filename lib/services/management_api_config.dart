import 'hosted_auth_config.dart';

/// Public endpoint only. Credentials come from the existing signed-in session.
class ManagementApiConfig {
  const ManagementApiConfig({required this.baseUri, required this.publicKey});
  final Uri baseUri;
  final String publicKey;

  static ManagementApiConfig? fromDefines(HostedAuthConfig? auth) =>
      parse(const String.fromEnvironment('MANAGEMENT_API_URL'), auth);

  static ManagementApiConfig? parse(String value, HostedAuthConfig? auth) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (auth == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.origin != auth.url ||
        !{
          '/functions/v1/management',
          '/functions/v1/management/',
        }.contains(uri.path)) {
      throw const FormatException(
        'Management API must use this build’s Supabase project and management function.',
      );
    }
    return ManagementApiConfig(
      baseUri: uri.replace(path: '/functions/v1/management'),
      publicKey: auth.publishableKey,
    );
  }
}
