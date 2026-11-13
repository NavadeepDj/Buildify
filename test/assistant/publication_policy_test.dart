import 'dart:async';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool fail = false;
  Completer<void>? scopeGate;
  @override
  Future<void> write({
    required String key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (fail) throw StateError('Storage unavailable');
    if (key == 'model_access_scope' && scopeGate != null) {
      await scopeGate!.future;
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class _Bridge implements ServerBridge {
  final calls = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Unexpected runtime action');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Storage storage;
  late _Bridge bridge;
  late AiServerController controller;
  setUp(() {
    storage = _Storage();
    bridge = _Bridge();
    controller = AiServerController(
      bridge: bridge,
      secureStorage: storage,
      initialize: false,
    );
  });
  tearDown(() => controller.dispose());
  test('fresh controller denies both public tunnel entry points', () async {
    expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
    expect(await controller.startTunnel(), isFalse);
    await expectLater(controller.startNamedTunnel('test'), throwsStateError);
    expect(bridge.calls, isEmpty);
  });
  test(
    'public intent requires a configured key and persists only intent',
    () async {
      await expectLater(
        controller.setModelAccessScope(ModelAccessScope.public),
        throwsStateError,
      );
      await controller.regenerateApiKey();
      await controller.setRequireApiKey(true);
      await controller.setModelAccessScope(ModelAccessScope.public);
      expect(storage.values['model_access_scope'], 'public');
      // Configuring a key cannot prove it is applied to an already-running process.
      expect(await controller.startTunnel(), isFalse);
      expect(bridge.calls, isEmpty);
    },
  );
  test('turning auth off or rotating a key revokes public intent', () async {
    await controller.regenerateApiKey();
    await controller.setRequireApiKey(true);
    await controller.setModelAccessScope(ModelAccessScope.public);
    await controller.setRequireApiKey(false);
    expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
    await controller.setRequireApiKey(true);
    await controller.setModelAccessScope(ModelAccessScope.public);
    await controller.regenerateApiKey();
    expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
  });
  test(
    'storage failure cannot grant public intent or undo local revocation',
    () async {
      await controller.regenerateApiKey();
      await controller.setRequireApiKey(true);
      storage.fail = true;
      await expectLater(
        controller.setModelAccessScope(ModelAccessScope.public),
        throwsStateError,
      );
      expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
      storage.fail = false;
      await controller.setModelAccessScope(ModelAccessScope.public);
      storage.fail = true;
      await expectLater(
        controller.setModelAccessScope(ModelAccessScope.deviceNetwork),
        throwsStateError,
      );
      expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
      expect(bridge.calls, isEmpty);
    },
  );
  test('a late public save cannot override a newer private decision', () async {
    await controller.regenerateApiKey();
    await controller.setRequireApiKey(true);
    storage.scopeGate = Completer<void>();
    final enabling = controller.setModelAccessScope(ModelAccessScope.public);
    await Future<void>.delayed(Duration.zero);
    final disabling = controller.setModelAccessScope(
      ModelAccessScope.deviceNetwork,
    );
    expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
    storage.scopeGate!.complete();
    await enabling;
    await disabling;
    expect(controller.modelAccessScope, ModelAccessScope.deviceNetwork);
    expect(storage.values['model_access_scope'], 'deviceNetwork');
  });
}
