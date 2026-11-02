import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildify_flutter/services/secure_auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'restored sessions are isolated by hosted project and deletion is scoped',
    () async {
      const development = SecureAuthStorage(
        projectHost: 'development.supabase.co',
      );
      const staging = SecureAuthStorage(projectHost: 'staging.supabase.co');
      await development.initialize();
      expect(await development.hasAccessToken(), false);
      await development.persistSession('development-session-fixture');
      await staging.persistSession('staging-session-fixture');
      expect(await development.hasAccessToken(), true);
      expect(
        await const SecureAuthStorage(
          projectHost: 'development.supabase.co',
        ).accessToken(),
        'development-session-fixture',
      );
      await development.removePersistedSession();
      expect(await development.accessToken(), isNull);
      expect(await staging.accessToken(), 'staging-session-fixture');
    },
  );
  test(
    'PKCE verifier storage stays distinct from sessions and other projects',
    () async {
      const development = SecurePkceStorage(
        projectHost: 'development.supabase.co',
      );
      const staging = SecurePkceStorage(projectHost: 'staging.supabase.co');
      const session = SecureAuthStorage(projectHost: 'development.supabase.co');
      await session.persistSession('session-fixture');
      await development.setItem(key: 'verifier', value: 'verifier-fixture');
      expect(await staging.getItem(key: 'verifier'), isNull);
      expect(await development.getItem(key: 'verifier'), 'verifier-fixture');
      await development.removeItem(key: 'verifier');
      expect(await development.getItem(key: 'verifier'), isNull);
      expect(await session.accessToken(), 'session-fixture');
    },
  );
}
