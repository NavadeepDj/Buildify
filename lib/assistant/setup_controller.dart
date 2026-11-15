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
    this.failureCode,
    this.availableMemoryGiB,
    this.requiredMemoryGiB,
  });
  final bool busy;
  final ModelOperationPlan? plan;
  final ModelCandidate? candidate;
  final ModelOperationRecord? record;
  final String? message, endpoint;
  final Duration? inferenceDuration;
  final String? failureCode;
  final double? availableMemoryGiB, requiredMemoryGiB;
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
    String? modelId,
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
        allowReducedContext: true,
      );
      // Unknown binary support is shown as an explicit trial, never eligible.
      final candidates = result.candidates.where(
        (c) =>
            (modelId == null || c.model.id == modelId) &&
            c.blockers.every((b) => b == 'runtime_verification_required'),
      );
      if (candidates.isEmpty) {
        final closest =
            result.candidates
                .where((c) => modelId == null || c.model.id == modelId)
                .firstOrNull;
        final available = metrics.value?.availableMemoryGiB;
        final required =
            closest?.model.requirements == null
                ? null
                : (closest!.estimatedMemoryBytes! +
                        const ModelRecommendationService().memoryReserveBytes) /
                    1073741824;
        final memoryBlocked =
            closest?.blockers.contains('insufficient_memory') == true;
        state = AssistantSetupState(
          failureCode:
              memoryBlocked ? 'insufficient_memory' : 'no_compatible_plan',
          availableMemoryGiB: available,
          requiredMemoryGiB: required,
          message:
              memoryBlocked && available != null && required != null
                  ? 'Not enough available memory: ${available.toStringAsFixed(2)} GiB available; ${required.toStringAsFixed(2)} GiB required for ${closest!.model.name}, including the host reserve. Free memory and retry. No model is waiting for approval.'
                  : 'No compatible model plan could be prepared. Check memory, storage and model support, then retry. No model is waiting for approval.',
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
        contextTokens: candidate.contextTokens ?? r.contextTokens,
        scope: ModelAccessScope.deviceNetwork,
        stopExisting: stopExisting,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      state = AssistantSetupState(
        plan: plan,
        candidate: candidate,
        message:
            '${plan.contextTokens < r.contextTokens ? 'Using a reduced ${plan.contextTokens}-token context to fit available memory. ' : ''}This candidate fits the resource budget. Runtime compatibility will be tested during startup and inference.',
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
