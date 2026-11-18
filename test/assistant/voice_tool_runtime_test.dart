import 'package:buildify_flutter/assistant/voice_tool_runtime.dart';
import 'package:buildify_flutter/backend/embedded_backend.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bridge implements ServerBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native action');
}

class _Controller extends AiServerController {
  void replaceArtifact() {
    final old = snapshot.models.first;
    state = state.copyWith(
      models: [
        ModelProfile(
          id: old.id,
          name: old.name,
          fileName: 'replacement.gguf',
          downloadUrl: old.downloadUrl,
          sizeLabel: old.sizeLabel,
          speed: old.speed,
          quality: old.quality,
          requiredRamGb: old.requiredRamGb,
          description: old.description,
        ),
      ],
    );
  }

  _Controller() : super(bridge: _Bridge(), initialize: false) {
    state = state.copyWith(
      models: const [
        ModelProfile(
          id: 'fixture',
          name: 'Fixture',
          fileName: 'fixture.gguf',
          downloadUrl: 'https://example.invalid/fixture',
          sizeLabel: 'test',
          speed: 'test',
          quality: 'test',
          requiredRamGb: 1,
          description: 'test',
        ),
      ],
      selectedModelId: 'fixture',
      logs: [
        ServerLog(
          'Bearer very-private-token https://example.invalid/?key=sensitive',
          LogType.warning,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Controller host;
  late EmbeddedBackendService backend;
  late ProviderContainer container;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    host = _Controller();
    backend = EmbeddedBackendService(autoHydrate: false);
    container = ProviderContainer(
      overrides: [
        aiServerProvider.overrideWith((ref) => host),
        embeddedBackendProvider.overrideWithValue(backend),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  test('remote generation change waits for local action approval', () async {
    final runtime = container.read(voiceToolRuntimeProvider);
    final before = host.snapshot.temperature;
    final request = await runtime.invoke('set_temperature', {
      'temperature': 0.4,
    });
    expect(request['state'], 'needs_approval');
    expect(host.snapshot.temperature, before);
    await container
        .read(voiceActionsProvider.notifier)
        .approve(request['action_id'] as String);
    expect(host.snapshot.temperature, 0.4);
    expect(
      container
          .read(voiceActionsProvider.notifier)
          .status(request['action_id'] as String)['state'],
      'succeeded',
    );
  });
  test('changed model identity invalidates a pending approval', () async {
    final request = await container.read(voiceToolRuntimeProvider).invoke(
      'download_model',
      {'model_id': 'fixture'},
    );
    host.replaceArtifact();
    await container
        .read(voiceActionsProvider.notifier)
        .approve(request['action_id'] as String);
    final status = container
        .read(voiceActionsProvider.notifier)
        .status(request['action_id'] as String);
    expect(status['state'], 'failed');
    expect(
      (status['result'] as Map)['error'],
      'model_changed_request_new_approval',
    );
  });
  test(
    'diagnostics redact credentials and URLs before leaving the app',
    () async {
      final result = await container
          .read(voiceToolRuntimeProvider)
          .invoke('get_model_diagnostics', {});
      expect(result.toString(), isNot(contains('very-private-token')));
      expect(result.toString(), isNot(contains('example.invalid')));
      expect(result['cause_confirmed'], false);
    },
  );
  test(
    'foreign IDs and arbitrary download URLs cannot create actions',
    () async {
      final runtime = container.read(voiceToolRuntimeProvider);
      expect(
        (await runtime.invoke('delete_model', {'model_id': 'foreign'}))['ok'],
        false,
      );
      expect(
        (await runtime.invoke('get_project', {'project_id': 'foreign'}))['ok'],
        false,
      );
      expect(
        (await runtime.invoke('download_model', {
          'model_id': 'fixture',
          'url': 'https://evil.invalid',
        }))['ok'],
        false,
      );
      expect(container.read(voiceActionsProvider), isEmpty);
    },
  );
  test(
    'stopped model verification reports failure instead of false success',
    () async {
      final request = await container
          .read(voiceToolRuntimeProvider)
          .invoke('verify_model', {});
      await Future<void>.delayed(Duration.zero);
      final status = container
          .read(voiceActionsProvider.notifier)
          .status(request['action_id'] as String);
      expect(status['state'], 'failed');
      expect((status['result'] as Map)['health_verified'], false);
    },
  );
  test('untrusted repository URLs and reserved routes are rejected', () async {
    final runtime = container.read(voiceToolRuntimeProvider);
    for (final url in [
      'http://github.com/owner/repo',
      'https://github.com.evil.invalid/o/r',
      'https://github.com/o/r?token=secret',
      'https://github.com/o/r/tree/main',
    ]) {
      expect(
        (await runtime.invoke('import_static_project', {
          'name': 'fixture',
          'repo_url': url,
        }))['ok'],
        false,
      );
    }
    expect(container.read(voiceActionsProvider), isEmpty);
  });
}
