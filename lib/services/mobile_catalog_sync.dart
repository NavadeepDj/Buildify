import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../backend/embedded_backend.dart';

class MobileCatalogSync {
  MobileCatalogSync(this._client, this._getBackend) {
    _authSubscription = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _sessionGeneration++;
        _syncedAccount = null;
        _syncedProjects = null;
        _deviceName = null;
      }
      _schedule();
    }, onError: (Object _) => _schedule());
    _schedule();
  }

  final SupabaseClient _client;
  final EmbeddedBackendService Function() _getBackend;
  late final StreamSubscription<AuthState> _authSubscription;
  StreamSubscription<List<BackendProject>>? _projectSubscription;
  EmbeddedBackendService? _backend;
  Timer? _retry;
  String? _installationId;
  String? _deviceName;
  String? _syncedAccount;
  String? _syncedProjects;
  int _sessionGeneration = 0;
  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  Future<String> _loadInstallationId() async {
    const storage = FlutterSecureStorage();
    const key = 'buildify.mobile.installation_id';
    final saved = await storage.read(key: key);
    if (saved != null) return saved;
    final id = const Uuid().v4();
    await storage.write(key: key, value: id);
    return id;
  }

  Future<String> _loadDeviceName() async {
    final fallback = Platform.isAndroid ? 'Android' : 'iPhone';
    try {
      final name = await const MethodChannel(
        'buildify.ai/server',
      ).invokeMethod<String>('getMobileDeviceName');
      return name == null || name.trim().isEmpty ? fallback : name.trim();
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }

  String? get _accountId {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.isExpired ||
        session.user.emailConfirmedAt == null) {
      return null;
    }
    return session.user.id;
  }

  void _schedule() {
    if (_disposed) return;
    _pending = true;
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending && !_disposed) {
        _pending = false;
        await _sync();
      }
    } catch (_) {
      if (!_disposed && _accountId != null) {
        debugPrint(
          'Buildify mobile catalog sync failed. Retrying in 30 seconds.',
        );
        _retry ??= Timer(const Duration(seconds: 30), () {
          _retry = null;
          _schedule();
        });
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _sync() async {
    final account = _accountId;
    final generation = _sessionGeneration;
    if (account == null) {
      _retry?.cancel();
      _retry = null;
      _syncedAccount = null;
      _syncedProjects = null;
      _deviceName = null;
      return;
    }

    final backend = _backend ??= _getBackend();
    _projectSubscription ??= backend.stream
        .map((state) => state.projects)
        .distinct()
        .listen((_) => _schedule());

    // A pending or failed local load must never publish an empty catalog.
    final projects =
        backend.projectsHydrated
            ? [
              for (final project in backend.state.projects)
                {'project_id': project.id, 'project_name': project.name},
            ]
            : null;
    final snapshot = jsonEncode(projects);
    if (_syncedAccount == account && _syncedProjects == snapshot) return;

    _installationId ??= await _loadInstallationId();
    final name = _deviceName ?? await _loadDeviceName();
    if (_disposed ||
        _accountId != account ||
        generation != _sessionGeneration) {
      return;
    }
    _deviceName = name;

    await _client.rpc<void>(
      'sync_mobile_catalog',
      params: {
        'account_id': account,
        'installation_id': _installationId,
        'mobile_name': name,
        'mobile_platform': Platform.isAndroid ? 'android' : 'ios',
        'projects': projects,
      },
    );
    if (generation != _sessionGeneration) return;
    _syncedAccount = account;
    _syncedProjects = snapshot;
    _retry?.cancel();
    _retry = null;
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_authSubscription.cancel());
    unawaited(_projectSubscription?.cancel());
  }
}
