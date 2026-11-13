import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import 'controller_model_runtime.dart';
import 'model_operations.dart';
import 'model_recommendation.dart';

class AssistantSetupState {
  const AssistantSetupState({
    this.busy = false,
    this.plan,
    this.candidate,
    this.record,
    this.message,
    this.endpoint,
    this.inferenceDuration,
  });
  final bool busy;
  final ModelOperationPlan? plan;
  final ModelCandidate? candidate;
  final ModelOperationRecord? record;
  final String? message, endpoint;
  final Duration? inferenceDuration;
}

final assistantSetupProvider =
    StateNotifierProvider<AssistantSetupController, AssistantSetupState>((ref) {
      return AssistantSetupController(ref.watch(aiServerProvider.notifier));
    });

class AssistantSetupController extends StateNotifier<AssistantSetupState> {
  AssistantSetupController(this.host) : super(const AssistantSetupState());
  final AiServerController host;
  Future<ModelOperationExecutor>? _executor;
  ControllerModelRuntime? _runtime;
  bool _cancelRequested = false;
  Future<ModelOperationExecutor> _getExecutor() =>
      _executor ??= () async {
        final support = await getApplicationSupportDirectory();
        final runtime = ControllerModelRuntime(host);
        _runtime = runtime;
        return ModelOperationExecutor(
          journal: FileModelOperationJournal(
            Directory('${support.path}/assistant_operations'),
          ),
          runtime: runtime,
        );
      }();

  Future<void> prepare({
    ModelPreference preference = ModelPreference.balanced,
    String task = 'short_answers',
    bool stopExisting = false,
  }) async {
    if (state.busy) return;
    state = const AssistantSetupState(
      busy: true,
      message: 'Checking device resources…',
    );
    try {
      final metrics = await host.inspectForAssistant();
      if (!mounted) return;
      final now = DateTime.now();
      final platform = metrics.value?.platform;
      if (platform == null) throw StateError('Metrics unavailable');
      final result = const ModelRecommendationService().recommend(
        models: host.snapshot.models,
        device: metrics,
        runtime: RuntimeCompatibility(readAt: now, platform: platform),
        now: now,
        preference: preference,
        task: task,
      );
      // Unknown binary support is shown as an explicit trial, never eligible.
      final candidates = result.candidates.where(
        (c) => c.blockers.every((b) => b == 'runtime_verification_required'),
      );
      if (candidates.isEmpty) {
        state = const AssistantSetupState(
          message:
              'A suitable candidate could not be prepared. Check available memory, storage and the model catalog, then retry.',
        );
        return;
      }
      final candidate = candidates.first;
      final r = candidate.model.requirements!;
      final plan = ModelOperationPlan(
        id: const Uuid().v4(),
        modelId: candidate.model.id,
        artifactSha256: r.sha256,
        downloadBytes: r.bytes,
        contextTokens: r.contextTokens,
        scope: ModelAccessScope.deviceNetwork,
        stopExisting: stopExisting,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      state = AssistantSetupState(
        plan: plan,
        candidate: candidate,
        message:
            'This candidate fits the resource budget. Runtime compatibility will be tested during startup and inference.',
      );
    } catch (_) {
      if (mounted) {
        state = const AssistantSetupState(
          message:
              'Device inspection was unavailable. Retry or use the manual model controls.',
        );
      }
    }
  }

  Future<void> approveAndRun() async {
    final plan = state.plan;
    final candidate = state.candidate;
    if (state.busy || plan == null || candidate == null) return;
    _cancelRequested = false;
    state = AssistantSetupState(
      busy: true,
      plan: plan,
      candidate: candidate,
      message: 'Preparing the approved operation…',
    );
    try {
      final executor = await _getExecutor();
      if (_cancelRequested) {
        if (mounted) {
          state = const AssistantSetupState(
            message: 'Cancelled before execution.',
          );
        }
        return;
      }
      final approval = LocalPlanApproval.approve(plan, DateTime.now());
      final result = await executor.run(
        plan,
        approval,
        onProgress: (record) {
          if (mounted) {
            state = AssistantSetupState(
              busy: true,
              plan: plan,
              candidate: candidate,
              record: record,
            );
          }
        },
      );
      if (!mounted) return;
      final success = result.state == ModelOperationState.succeeded;
      state = AssistantSetupState(
        plan: plan,
        candidate: candidate,
        record: result,
        endpoint: success ? host.apiBaseUrl : null,
        inferenceDuration: success ? _runtime?.inferenceDuration : null,
        message:
            success
                ? 'The model answered a real test request.'
                : result.state == ModelOperationState.cancelled
                ? 'Setup was cancelled.'
                : 'Setup needs attention (${result.errorCode ?? result.state.name}). Check the model screen before retrying.',
      );
    } catch (_) {
      if (mounted) {
        state = AssistantSetupState(
          plan: plan,
          candidate: candidate,
          message:
              'The operation could not continue. Review the device state and prepare a fresh plan.',
        );
      }
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final plan = state.plan;
    final future = _executor;
    if (plan != null && future != null) {
      try {
        await (await future).cancel(plan.id);
      } catch (_) {
        /* Result remains under executor ownership. */
      }
    }
  }
}
