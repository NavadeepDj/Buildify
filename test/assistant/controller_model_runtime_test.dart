import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:buildify_flutter/assistant/controller_model_runtime.dart';
import 'package:buildify_flutter/assistant/host_inspection.dart';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/models/model_requirements.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bridge implements ServerBridge {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected native call');
}

class _Controller extends AiServerController {
  _Controller(this.file, ModelProfile model)
    : super(bridge: _Bridge(), initialize: false) {
    state = state.copyWith(models: [model], selectedModelId: model.id);
  }
  final File file;
  @override
  Future<File> modelArtifactForAssistant(String id) async => file;
  @override
  Future<InspectionReading<AssistantDeviceCapabilities>>
  inspectForAssistant() async => InspectionReading(
    status: InspectionStatus.partial,
    readAt: DateTime.now(),
    value: AssistantDeviceCapabilities(
      platform: AssistantHostPlatform.windows,
      availableMemoryGiB: 8,
      freeStorageGiB: 20,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'existing artifact must match exact bytes/hash before being accepted',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('assistant-artifact-');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = [71, 71, 85, 70, 1, 2, 3, 4];
      final hash = sha256.convert(bytes).toString();
      final file = await File('${dir.path}/model.gguf').writeAsBytes(bytes);
      final model = ModelProfile(
        id: 'test',
        name: 'test',
        fileName: 'model.gguf',
        downloadUrl: 'https://huggingface.co/unused',
        sizeLabel: '8 B',
        speed: 'test',
        quality: 'test',
        requiredRamGb: 1,
        description: 'Synthetic artifact identity fixture',
        requirements: ModelRequirements(
          bytes: bytes.length,
          sha256: hash,
          sourceRevision: 'a' * 40,
          license: 'test-only',
          contextTokens: 2048,
          runtimeOverheadBytes: 1,
          contextMemoryBytes: 1,
          format: 'gguf',
          runtime: 'llama.cpp',
        ),
      );
      final controller = _Controller(file, model);
      addTearDown(controller.dispose);
      final runtime = ControllerModelRuntime(controller);
      final now = DateTime.now();
      final plan = ModelOperationPlan(
        id: 'verify-only',
        modelId: model.id,
        artifactSha256: hash,
        downloadBytes: bytes.length,
        scope: ModelAccessScope.deviceNetwork,
        stopExisting: false,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 1)),
      );
      await runtime.verifyArtifact(plan);
      expect(
        controller.snapshot.downloads[model.id]!.status,
        ModelDownloadStatus.downloaded,
      );
      await file.writeAsBytes([0, 0, 0, 0, 0, 0, 0, 0]);
      await expectLater(
        runtime.verifyArtifact(plan),
        throwsA(isA<ModelOperationFailure>()),
      );
    },
  );
}
