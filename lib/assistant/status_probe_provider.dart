import 'dart:io';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_server_provider.dart';
import 'status_probe_server.dart';
import 'setup_controller.dart';
import 'model_operations.dart';
import 'model_recommendation.dart';
import '../models/ai_server_models.dart';
import 'voice_tool_specs.dart';
import 'voice_tool_runtime.dart';

final voiceSetupRequestsProvider = StateProvider<int>((ref) => 0);
final pendingVoiceRequestsProvider = Provider<int>((ref) {
  final actions =
      ref
          .watch(voiceActionsProvider)
          .where((a) => a.state == 'needs_approval')
          .length;
  if (ref.watch(voiceSetupRequestsProvider) == 0) return actions;
  final setup = ref.watch(assistantSetupProvider);
  return actions + (setup.busy || setup.record == null ? 1 : 0);
});

/// Disabled unless explicitly launched with a temporary environment token.
/// Inspection reuses the live bridge; setup initializes the existing controller
/// only after an explicit plan request. Execution still needs local UI approval.
final statusProbeProvider = FutureProvider<StatusProbeServer?>((ref) async {
  if (!Platform.isWindows) return null;
  final token = Platform.environment['BUILDIFY_STATUS_TOKEN'];
  if (token == null || token.isEmpty) return null;
  final tools = ref.watch(assistantInspectionToolsProvider);
  var disposed = false;
  bool preparing = false;
  bool requested = false;
  String? preparationError;
  String? requestedModelId;
  Map<String, Object?> setupStatus() {
    if (!requested) {
      return {'ok': true, 'state': 'not_requested', 'health_verified': false};
    }
    if (preparing) {
      return {
        'ok': true,
        'state': 'preparing_plan',
        'health_verified': false,
        'summary':
            'Checking resources. A plan is not ready yet; do not ask for approval.',
        'next_action': 'check_get_setup_status',
      };
    }
    final state = ref.read(assistantSetupProvider);
    final plan = state.plan;
    final host = ref.read(aiServerProvider);
    final verified =
        state.record?.state == ModelOperationState.succeeded &&
        host.status == ServerStatus.running &&
        host.selectedModelId == plan?.modelId &&
        ref.read(aiServerProvider.notifier).apiBaseUrl == state.endpoint;
    return {
      'ok': preparationError == null && plan != null,
      'state':
          preparationError ??
          (state.busy
              ? (state.record?.state.name ?? 'preparing')
              : state.record?.state == ModelOperationState.succeeded
              ? (verified ? 'succeeded' : 'inactive')
              : state.record?.state.name ??
                  (plan == null
                      ? 'no_compatible_plan'
                      : DateTime.now().isBefore(plan.expiresAt)
                      ? 'needs_approval'
                      : 'plan_expired')),
      'health_verified': verified,
      if (state.failureCode != null) 'error_code': state.failureCode,
      if (state.availableMemoryGiB != null)
        'available_memory_gib': state.availableMemoryGiB,
      if (state.requiredMemoryGiB != null)
        'required_memory_gib': state.requiredMemoryGiB,
      if (state.message != null) 'summary': state.message,
      if (plan != null) 'plan_id': plan.id,
      if (state.candidate != null) 'model': state.candidate!.model.name,
      if (plan != null) 'download_bytes': plan.downloadBytes,
      if (state.record?.errorCode != null)
        'error_code': state.record!.errorCode,
      'approval_ready':
          !state.busy &&
          plan != null &&
          state.record == null &&
          DateTime.now().isBefore(plan.expiresAt),
      'approval_location':
          'Voice requests → Model setup request → Approve and run model',
      'next_action':
          verified
              ? 'use_connection_details_in_buildify'
              : state.busy
              ? 'check_get_setup_status'
              : plan == null
              ? (state.failureCode == 'insufficient_memory'
                  ? 'free_memory_and_retry'
                  : 'resolve_setup_blocker_and_retry')
              : 'review_in_buildify',
    };
  }

  Future<void> prepare() async {
    try {
      final host = ref.read(aiServerProvider.notifier);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (host.snapshot.models.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (disposed) return;
      await ref
          .read(assistantSetupProvider.notifier)
          .prepare(
            preference: ModelPreference.speed,
            task: 'short_answers',
            stopExisting: false,
            modelId: requestedModelId,
          );
    } catch (_) {
      preparationError = 'preparation_unavailable';
    } finally {
      preparing = false;
    }
  }

  StatusProbeServer? server;
  ref.onDispose(() {
    disposed = true;
    server?.close();
  });
  Map<String, Object?> requestSetup({String? modelId}) {
    final state = requested ? ref.read(assistantSetupProvider) : null;
    if (preparing ||
        state?.busy == true ||
        (state?.plan != null &&
            state?.record == null &&
            DateTime.now().isBefore(state!.plan!.expiresAt))) {
      return setupStatus();
    }
    requested = true;
    requestedModelId = modelId;
    preparing = true;
    preparationError = null;
    ref.read(voiceSetupRequestsProvider.notifier).state++;
    unawaited(prepare());
    return setupStatus();
  }

  server = await StatusProbeServer.start(
    token: token,
    setupStatus: setupStatus,
    requestSetup: () => requestSetup(),
    listTools: () => voiceToolSpecs.map((s) => s.toJson()).toList(),
    invokeTool: (name, args) async {
      final spec = voiceToolSpecs.where((s) => s.name == name).firstOrNull;
      final normalized = spec?.normalize(args) ?? args;
      if (spec == null || !spec.accepts(normalized)) {
        return {'ok': false, 'error': 'invalid_tool_or_arguments'};
      }
      if (name == 'request_model_setup') return requestSetup();
      if (name == 'request_specific_model_setup') {
        return requestSetup(modelId: normalized['model_id'] as String);
      }
      if (name == 'get_setup_status') return setupStatus();
      return ref.read(voiceToolRuntimeProvider).invoke(name, normalized);
    },
    inspect: () async {
      final result = await tools.invoke('get_runtime_state');
      if (result.data == null) throw StateError('Inspection unavailable');
      return result.data!;
    },
  );
  if (disposed) await server.close();
  return server;
});
