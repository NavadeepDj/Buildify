import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keep session refresh tokens out of shared preferences and project metadata.
class SecureAuthStorage extends LocalStorage {
  const SecureAuthStorage({
    required this.projectHost,
    this.storage = const FlutterSecureStorage(),
  });

  final String projectHost;
  final FlutterSecureStorage storage;
  String get _key => 'buildify.auth.$projectHost';

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => storage.delete(key: _key);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage({
    required this.projectHost,
    this.storage = const FlutterSecureStorage(),
  });
  final String projectHost;
  final FlutterSecureStorage storage;
  String _key(String key) => 'buildify.pkce.$projectHost.$key';
  @override
  Future<String?> getItem({required String key}) =>
      storage.read(key: _key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.write(key: _key(key), value: value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.delete(key: _key(key));
}
