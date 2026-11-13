import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/ai_server_models.dart';

enum ModelOperationState {
  preparing,
  downloading,
  verifyingArtifact,
  configuring,
  starting,
  verifyingInference,
  succeeded,
  failed,
  cancelled,
  needsReview,
}

class ModelOperationPlan {
  ModelOperationPlan({
    required this.id,
    required this.modelId,
    required this.artifactSha256,
    required this.downloadBytes,
    required this.scope,
    required this.stopExisting,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
        modelId.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(artifactSha256) ||
        downloadBytes <= 0 ||
        !expiresAt.isAfter(createdAt)) {
      throw ArgumentError('Invalid model plan');
    }
  }
  final String id, modelId, artifactSha256;
  final int downloadBytes;
  final ModelAccessScope scope;
  final bool stopExisting;
  final DateTime createdAt, expiresAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'modelId': modelId,
    'artifactSha256': artifactSha256,
    'downloadBytes': downloadBytes,
    'scope': scope.name,
    'stopExisting': stopExisting,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// Only an explicit local UI decision should call approve. This handle has no
/// JSON constructor and is never accepted from cloud tool arguments.
class LocalPlanApproval {
  LocalPlanApproval._(this.digest, this.approvedAt);
  final String digest;
  final DateTime approvedAt;
  static LocalPlanApproval approve(ModelOperationPlan plan, DateTime now) {
    if (now.isBefore(plan.createdAt) || !now.isBefore(plan.expiresAt)) {
      throw StateError('Plan expired or not yet valid');
    }
    return LocalPlanApproval._(plan.digest, now.toUtc());
  }
}

class ModelOperationRecord {
  const ModelOperationRecord({
    required this.id,
    required this.planDigest,
    required this.state,
    required this.updatedAt,
    this.errorCode,
  });
  final String id, planDigest;
  final ModelOperationState state;
  final DateTime updatedAt;
  final String? errorCode;
  bool get terminal => {
    ModelOperationState.succeeded,
    ModelOperationState.failed,
    ModelOperationState.cancelled,
    ModelOperationState.needsReview,
  }.contains(state);
  Map<String, Object?> toJson() => {
    'id': id,
    'planDigest': planDigest,
    'state': state.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'errorCode': errorCode,
  };
  factory ModelOperationRecord.fromJson(Map<String, dynamic> json) =>
      ModelOperationRecord(
        id: json['id'] as String,
        planDigest: json['planDigest'] as String,
        state: ModelOperationState.values.byName(json['state'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        errorCode: json['errorCode'] as String?,
      );
}

abstract interface class ModelOperationJournal {
  Future<ModelOperationRecord?> read(String id);
  Future<void> write(ModelOperationRecord record);
}

/// The directory is selected by the app, never by a remote plan. Files contain
/// only operation identity/state and fixed errors, no prompts, paths or secrets.
class FileModelOperationJournal implements ModelOperationJournal {
  FileModelOperationJournal(this.directory);
  final Directory directory;
  File _file(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw ArgumentError('Invalid operation ID');
    }
    return File('${directory.path}/$id.json');
  }

  @override
  Future<ModelOperationRecord?> read(String id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    final record = ModelOperationRecord.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
    if (record.id != id) {
      throw const FormatException('Operation identity mismatch');
    }
    return record;
  }

  @override
  Future<void> write(ModelOperationRecord record) async {
    final f = _file(record.id);
    await directory.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(record.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}

class OperationCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const ModelOperationFailure('cancelled');
  }
}

class ModelOperationFailure implements Exception {
  const ModelOperationFailure(this.code);
  final String code;
}

abstract interface class ModelOperationRuntime {
  Future<void> prepare(ModelOperationPlan plan);
  Future<void> download(
    ModelOperationPlan plan,
    OperationCancellation cancellation,
  );
  Future<void> verifyArtifact(ModelOperationPlan plan);
  Future<void> configure(ModelOperationPlan plan);
  Future<void> start(ModelOperationPlan plan);
  Future<void> verifyInference(ModelOperationPlan plan);

  /// Cancel only resources owned by this operation; do not delete user projects.
  Future<void> cancel(ModelOperationPlan plan);
}

class ModelOperationExecutor {
  ModelOperationExecutor({
    required this.journal,
    required this.runtime,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final ModelOperationJournal journal;
  final ModelOperationRuntime runtime;
  final DateTime Function() _clock;
  String? _active;
  ModelOperationPlan? _activePlan;
  Future<void>? _cancelCleanup;
  OperationCancellation? _cancellation;
  bool get busy => _active != null;
  Future<void> cancel(String id) async {
    if (_active == id) {
      _cancellation?.cancel();
      _cancelCleanup ??= Future<void>.sync(() => runtime.cancel(_activePlan!));
      await _cancelCleanup;
    }
  }

  Future<ModelOperationRecord> run(
    ModelOperationPlan plan,
    LocalPlanApproval approval, {
    void Function(ModelOperationRecord)? onProgress,
  }) async {
    if (_active != null) throw const ModelOperationFailure('host_busy');
    final now = _clock().toUtc();
    if (approval.digest != plan.digest ||
        approval.approvedAt.isAfter(now) ||
        approval.approvedAt.isBefore(plan.createdAt) ||
        now.isBefore(plan.createdAt) ||
        !now.isBefore(plan.expiresAt)) {
      throw const ModelOperationFailure('approval_invalid');
    }
    _active = plan.id;
    _activePlan = plan;
    final cancellation = OperationCancellation();
    _cancellation = cancellation;
    Future<ModelOperationRecord> record(
      ModelOperationState state, [
      String? error,
    ]) async {
      final r = ModelOperationRecord(
        id: plan.id,
        planDigest: plan.digest,
        state: state,
        updatedAt: _clock().toUtc(),
        errorCode: error,
      );
      await journal.write(r);
      try {
        onProgress?.call(r);
      } catch (_) {
        /* Observers cannot alter execution. */
      }
      return r;
    }

    try {
      ModelOperationRecord? previous;
      try {
        previous = await journal.read(plan.id);
      } catch (_) {
        throw const ModelOperationFailure('journal_unreadable');
      }
      if (previous != null) {
        if (previous.planDigest != plan.digest) {
          throw const ModelOperationFailure('operation_id_conflict');
        }
        if (previous.terminal) return previous;
        return await record(
          ModelOperationState.needsReview,
          'interrupted_operation',
        );
      }
      for (final step in <(ModelOperationState, Future<void> Function())>[
        (ModelOperationState.preparing, () => runtime.prepare(plan)),
        (
          ModelOperationState.downloading,
          () => runtime.download(plan, cancellation),
        ),
        (
          ModelOperationState.verifyingArtifact,
          () => runtime.verifyArtifact(plan),
        ),
        (ModelOperationState.configuring, () => runtime.configure(plan)),
        (ModelOperationState.starting, () => runtime.start(plan)),
        (
          ModelOperationState.verifyingInference,
          () => runtime.verifyInference(plan),
        ),
      ]) {
        cancellation.check();
        await record(step.$1);
        await step.$2();
        cancellation.check();
      }
      return await record(ModelOperationState.succeeded);
    } on ModelOperationFailure catch (e) {
      if (e.code == 'operation_id_conflict' || e.code == 'journal_unreadable')
        rethrow;
      if (cancellation.isCancelled || e.code == 'cancelled') {
        try {
          _cancelCleanup ??= Future<void>.sync(() => runtime.cancel(plan));
          await _cancelCleanup;
        } catch (_) {
          return await record(
            ModelOperationState.needsReview,
            'cancel_cleanup_failed',
          );
        }
        return await record(ModelOperationState.cancelled, 'cancelled');
      }
      const allowed = {
        'artifact_invalid',
        'download_failed',
        'model_unavailable',
        'start_failed',
        'inference_failed',
        'settings_changed',
        'active_workload',
        'scope_invalid',
      };
      return await record(
        ModelOperationState.failed,
        allowed.contains(e.code) ? e.code : 'runtime_failed',
      );
    } catch (_) {
      return await record(ModelOperationState.needsReview, 'operation_failed');
    } finally {
      _active = null;
      _activePlan = null;
      _cancelCleanup = null;
      _cancellation = null;
    }
  }
}
