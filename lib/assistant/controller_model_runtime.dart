import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import 'host_inspection.dart';
import 'model_endpoint_verifier.dart';
import 'model_operations.dart';

/// Concrete local adapter. Dependencies are app-owned, never remote-supplied
/// paths/commands. The first workflow supports device/LAN scope only.
class ControllerModelRuntime implements ModelOperationRuntime {
  ControllerModelRuntime(this.controller);
  final AiServerController controller;
  http.Client? _downloadClient;
  bool _cancelled = false, _started = false;
  File? _partial;
  Duration? inferenceDuration;
  ModelProfile _model(ModelOperationPlan plan) {
    final matches = controller.snapshot.models.where(
      (m) => m.id == plan.modelId,
    );
    if (matches.length != 1) {
      throw const ModelOperationFailure('model_unavailable');
    }
    final model = matches.single;
    final r = model.requirements;
    if (r == null ||
        r.contextTokens != plan.contextTokens ||
        r.sha256 != plan.artifactSha256 ||
        r.bytes != plan.downloadBytes) {
      throw const ModelOperationFailure('settings_changed');
    }
    return model;
  }

  void _check() {
    if (_cancelled) throw const ModelOperationFailure('cancelled');
  }

  Future<void> _resources(ModelOperationPlan plan) async {
    final model = _model(plan);
    final reading = await controller.inspectForAssistant();
    final memory = reading.value?.availableMemoryGiB;
    if (!{
          InspectionStatus.observed,
          InspectionStatus.partial,
        }.contains(reading.status) ||
        memory == null ||
        memory * 1073741824 <
            model.requirements!.estimatedMemoryBytes + 536870912) {
      throw const ModelOperationFailure('settings_changed');
    }
    final file = await controller.modelArtifactForAssistant(plan.modelId);
    if (!await file.exists()) {
      final disk = reading.value?.freeStorageGiB;
      if (disk == null || disk * 1073741824 < plan.downloadBytes + 268435456) {
        throw const ModelOperationFailure('settings_changed');
      }
    }
  }

  @override
  Future<void> prepare(ModelOperationPlan plan) async {
    _cancelled = false;
    _started = false;
    inferenceDuration = null;
    _partial = null;
    _model(plan);
    if (plan.scope != ModelAccessScope.deviceNetwork) {
      throw const ModelOperationFailure('scope_invalid');
    }
    if (controller.snapshot.downloads.values.any(
      (d) => d.status == ModelDownloadStatus.downloading,
    )) {
      throw const ModelOperationFailure('active_workload');
    }
    final state = controller.snapshot.status;
    if (state != ServerStatus.stopped) {
      if (!plan.stopExisting || state != ServerStatus.running) {
        throw const ModelOperationFailure('active_workload');
      }
      await controller.stopServer();
      if (controller.snapshot.status != ServerStatus.stopped) {
        throw const ModelOperationFailure('active_workload');
      }
    }
    await controller.setModelAccessScope(plan.scope);
    await _resources(plan);
    _check();
  }

  @override
  Future<void> download(
    ModelOperationPlan plan,
    OperationCancellation cancellation,
  ) async {
    _check();
    final model = _model(plan);
    final file = await controller.modelArtifactForAssistant(plan.modelId);
    if (await file.exists()) return;
    final uri = Uri.parse(model.downloadUrl);
    if (uri.scheme != 'https' ||
        uri.host != 'huggingface.co' ||
        !uri.path.contains('/resolve/${model.requirements!.sourceRevision}/')) {
      throw const ModelOperationFailure('download_failed');
    }
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.assistant.part');
    _partial = partial;
    final client = http.Client();
    _downloadClient = client;
    final sink = partial.openWrite();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const ModelOperationFailure('download_failed');
      }
      var bytes = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        cancellation.check();
        _check();
        bytes += chunk.length;
        if (bytes > plan.downloadBytes) {
          throw const ModelOperationFailure('artifact_invalid');
        }
        sink.add(chunk);
      }
      await sink.flush();
      if (bytes != plan.downloadBytes) {
        throw const ModelOperationFailure('artifact_invalid');
      }
    } catch (_) {
      _check();
      rethrow;
    } finally {
      await sink.close();
      client.close();
      _downloadClient = null;
    }
  }

  @override
  Future<void> verifyArtifact(ModelOperationPlan plan) async {
    _check();
    final file = await controller.modelArtifactForAssistant(plan.modelId);
    final source = _partial ?? file;
    if (!await source.exists() || await source.length() != plan.downloadBytes) {
      throw const ModelOperationFailure('artifact_invalid');
    }
    final digest =
        await sha256
            .bind(
              source.openRead().map((chunk) {
                _check();
                return chunk;
              }),
            )
            .first;
    _check();
    if (digest.toString() != plan.artifactSha256) {
      throw const ModelOperationFailure('artifact_invalid');
    }
    if (_partial != null) {
      await source.rename(file.path);
      _partial = null;
    }
    controller.acceptVerifiedArtifactForAssistant(plan.modelId);
  }

  @override
  Future<void> configure(ModelOperationPlan plan) async {
    _check();
    await _resources(plan);
    _model(plan);
    controller.selectModel(plan.modelId);
    await controller.setModelAccessScope(plan.scope);
  }

  @override
  Future<void> start(ModelOperationPlan plan) async {
    _check();
    if (controller.snapshot.selectedModelId != plan.modelId ||
        controller.modelAccessScope != plan.scope) {
      throw const ModelOperationFailure('settings_changed');
    }
    _started = true;
    await controller.startServer(contextTokens: plan.contextTokens);
    _check();
    if (controller.snapshot.status != ServerStatus.running) {
      throw const ModelOperationFailure('start_failed');
    }
  }

  @override
  Future<void> verifyInference(ModelOperationPlan plan) async {
    _check();
    final verifier = ModelEndpointVerifier();
    try {
      inferenceDuration = await verifier.verify(
        port: controller.snapshot.port,
        apiKey:
            controller.snapshot.security.requireApiKey
                ? controller.snapshot.security.apiKey
                : null,
      );
      _check();
    } finally {
      verifier.close();
    }
  }

  @override
  Future<void> cancel(ModelOperationPlan plan) async {
    _cancelled = true;
    _downloadClient?.close();
    if (_started) {
      await controller.stopServer();
      _started = false;
    }
    // Leave a bounded partial artifact for explicit recovery/cleanup; never
    // delete a model that was already present before this operation.
  }
}
