import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Journal implements ModelOperationJournal {
  final records = <String, ModelOperationRecord>{};
  @override
  Future<ModelOperationRecord?> read(String id) async => records[id];
  @override
  Future<void> write(ModelOperationRecord r) async {
    records[r.id] = r;
  }
}

class _Runtime implements ModelOperationRuntime {
  final calls = <String>[];
  Completer<void>? gate;
  bool failInference = false;
  @override
  Future<void> prepare(ModelOperationPlan p) async {
    calls.add('prepare');
  }

  @override
  Future<void> download(ModelOperationPlan p, OperationCancellation c) async {
    calls.add('download');
    if (gate != null) await gate!.future;
  }

  @override
  Future<void> verifyArtifact(ModelOperationPlan p) async {
    calls.add('artifact');
  }

  @override
  Future<void> configure(ModelOperationPlan p) async {
    calls.add('configure');
  }

  @override
  Future<void> start(ModelOperationPlan p) async {
    calls.add('start');
  }

  @override
  Future<void> verifyInference(ModelOperationPlan p) async {
    calls.add('verify');
    if (failInference) throw StateError('secret-token');
  }

  @override
  Future<void> cancel(ModelOperationPlan p) async {
    calls.add('cancel');
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 13);
  ModelOperationPlan plan({String id = 'operation-1', bool stop = false}) =>
      ModelOperationPlan(
        id: id,
        modelId: 'tiny',
        artifactSha256: List.filled(64, 'a').join(),
        downloadBytes: 100,
        scope: ModelAccessScope.deviceNetwork,
        stopExisting: stop,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      );
  late _Journal journal;
  late _Runtime runtime;
  late ModelOperationExecutor executor;
  setUp(() {
    journal = _Journal();
    runtime = _Runtime();
    executor = ModelOperationExecutor(
      journal: journal,
      runtime: runtime,
      clock: () => now,
    );
  });
  test('records actual steps and requires inference before success', () async {
    final p = plan();
    final steps = <ModelOperationState>[];
    final r = await executor.run(
      p,
      LocalPlanApproval.approve(p, now),
      onProgress: (r) => steps.add(r.state),
    );
    expect(r.state, ModelOperationState.succeeded);
    expect(runtime.calls.last, 'verify');
    expect(steps, contains(ModelOperationState.verifyingInference));
    await executor.run(p, LocalPlanApproval.approve(p, now));
    expect(runtime.calls.length, 6);
  });
  test('changed plan and expired approval cannot execute', () async {
    final p = plan();
    await expectLater(
      executor.run(plan(stop: true), LocalPlanApproval.approve(p, now)),
      throwsA(isA<ModelOperationFailure>()),
    );
    final expired = ModelOperationExecutor(
      journal: journal,
      runtime: runtime,
      clock: () => now.add(const Duration(minutes: 6)),
    );
    await expectLater(
      expired.run(p, LocalPlanApproval.approve(p, now)),
      throwsA(isA<ModelOperationFailure>()),
    );
    expect(runtime.calls, isEmpty);
  });
  test('host lock, cancellation and safe terminal retry', () async {
    runtime.gate = Completer<void>();
    final p = plan();
    final pending = executor.run(p, LocalPlanApproval.approve(p, now));
    while (!runtime.calls.contains('download')) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = plan(id: 'other');
    await expectLater(
      executor.run(second, LocalPlanApproval.approve(second, now)),
      throwsA(isA<ModelOperationFailure>()),
    );
    executor.cancel(p.id);
    runtime.gate!.complete();
    final result = await pending;
    expect(result.state, ModelOperationState.cancelled);
    expect(runtime.calls, contains('cancel'));
    expect(runtime.calls, isNot(contains('start')));
    expect(executor.busy, isFalse);
  });
  test('interruption requires reconciliation, never replays a start', () async {
    final p = plan();
    journal.records[p.id] = ModelOperationRecord(
      id: p.id,
      planDigest: p.digest,
      state: ModelOperationState.starting,
      updatedAt: now,
    );
    expect(
      (await executor.run(p, LocalPlanApproval.approve(p, now))).state,
      ModelOperationState.needsReview,
    );
    expect(runtime.calls, isEmpty);
  });
  test('raw runtime errors stay out of journal and result', () async {
    runtime.failInference = true;
    final p = plan();
    final r = await executor.run(p, LocalPlanApproval.approve(p, now));
    expect(r.state, ModelOperationState.needsReview);
    expect(jsonEncode(r.toJson()), isNot(contains('secret')));
  });
  test('file journal roundtrips and rejects traversal', () async {
    final dir = await Directory.systemTemp.createTemp('buildify-operations-');
    addTearDown(() => dir.delete(recursive: true));
    final j = FileModelOperationJournal(dir);
    final p = plan();
    final r = ModelOperationRecord(
      id: p.id,
      planDigest: p.digest,
      state: ModelOperationState.starting,
      updatedAt: now,
    );
    await j.write(r);
    await j.write(
      ModelOperationRecord(
        id: p.id,
        planDigest: p.digest,
        state: ModelOperationState.succeeded,
        updatedAt: now,
      ),
    );
    expect((await j.read(p.id))!.state, ModelOperationState.succeeded);
    await expectLater(j.read('../outside'), throwsArgumentError);
  });
}
