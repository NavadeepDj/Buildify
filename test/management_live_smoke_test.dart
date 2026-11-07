import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:buildify_flutter/services/hosted_auth_config.dart';
import 'package:buildify_flutter/services/management_api_config.dart';
import 'package:buildify_flutter/services/management_account_service.dart';

/// Opt-in only. The private harness supplies temporary-user refresh tokens in
/// the test process environment, never dart-defines, source, logs or an APK.
void main() {
  test(
    'Dart client signs in with temporary sessions and reads its own deployed profile',
    () async {
      final auth = HostedAuthConfig.fromDefines()!;
      final config = ManagementApiConfig.fromDefines(auth)!;
      for (final label in ['A', 'B']) {
        final token = Platform.environment['HOSTANY_SMOKE_REFRESH_$label']!;
        final expected = Platform.environment['HOSTANY_SMOKE_USER_$label']!;
        final client = sb.SupabaseClient(
          auth.url,
          auth.publishableKey,
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        );
        try {
          await client.auth.setSession(token);
          final service = ManagementAccountService(
            config: config,
            sessions: SupabaseManagementSessionSource(client),
          );
          final profile = await service.fetchAccount();
          expect(profile.id == expected, true);
          expect(profile.displayName, 'Verified own profile');
          await client.auth.signOut(scope: sb.SignOutScope.local);
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
        } finally {
          await client.dispose();
        }
      }
    },
    skip: Platform.environment['HOSTANY_RUN_LIVE_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
