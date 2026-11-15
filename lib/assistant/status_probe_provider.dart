import 'dart:io';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/ai_server_provider.dart';
import 'status_probe_server.dart';
import 'setup_controller.dart';
import 'model_operations.dart';
import 'model_recommendation.dart';
import '../models/ai_server_models.dart';
import 'voice_tool_specs.dart';
import 'voice_tool_runtime.dart';
import 'voice_bridge_session.dart';
import 'model_endpoint_verifier.dart';
import 'model_endpoint_email.dart';
import 'model_stop_email.dart';

final voiceSetupRequestsProvider = StateProvider<int>((ref) => 0);
final voiceEndpointEmailProvider = StateProvider<Map<String, Object?>>(
  (ref) => const {'state': 'not_requested'},
);

Future<void> approveModelSetupFromOwnerUi(
  WidgetRef ref,
  ModelOperationPlan plan,
) async {
  final bridge = ref.read(statusProbeProvider).asData?.value;
  if (bridge != null && ref.read(voiceSetupRequestsProvider) > 0) {
    final result = await bridge.invokeLocalTool('confirm_model_setup', {
      'plan_id': plan.id,
    });
    if (result['ok'] != false) return;
  }
  await ref.read(assistantSetupProvider.notifier).approveAndRun();
}

final voiceRunningModelRequestProvider = StateProvider<Map<String, Object?>?>(
  (ref) => null,
);
final pendingVoiceRequestsProvider = Provider<int>((ref) {
  final actions =
      ref
          .watch(voiceActionsProvider)
          .where((a) => a.state == 'needs_approval')
          .length;
  final running = ref.watch(voiceRunningModelRequestProvider);
  if (running != null) {
    return actions +
        ({'needs_approval', 'publishing', 'failed'}.contains(running['state'])
            ? 1
            : 0);
  }
  if (ref.watch(voiceSetupRequestsProvider) == 0) return actions;
  final setup = ref.watch(assistantSetupProvider);
  return actions +
      (setup.record?.state == ModelOperationState.succeeded ? 0 : 1);
});

/// Android opts in through a memory-only pairing; Windows also supports the
/// existing temporary environment token used by the desktop launcher.
/// Inspection reuses the live bridge; setup initializes the existing controller
/// only after an explicit plan request. The paired owner can confirm with Go.
final statusProbeProvider = FutureProvider<StatusProbeServer?>((ref) async {
  final session = ref.watch(voiceBridgeSessionProvider);
  if (!Platform.isWindows && !Platform.isAndroid && session == null) {
    return null;
  }
  final token =
      session?.token ??
      (Platform.isWindows
          ? Platform.environment['BUILDIFY_STATUS_TOKEN']
          : null);
  if (token == null || token.isEmpty) return null;
  final tools = ref.watch(assistantInspectionToolsProvider);
  var disposed = false;
  bool preparing = false;
  bool requested = false;
  String? preparationError;
  String? requestedModelId;
  bool executingVoicePlan = false;
  String? publicationError;
  String? reusedModelId, reusedPlanId;
  DateTime? reuseExpiresAt;
  bool reuseApproved = false, reuseVerified = false;
  final emailSender = ModelEndpointEmailSender();
  final stopEmail = ModelStopEmail(
    findAction:
        (id) =>
            ref
                .read(voiceActionsProvider)
                .where((action) => action.id == id)
                .firstOrNull,
    deliver:
        (action) => emailSender.sendStopped(
          actionId: action.id,
          model: action.result!['model_name'] as String,
          stoppedAt: action.result!['stopped_at'] as String,
        ),
  );
  int emailGeneration = 0;
  DateTime? lastExplicitEmailResend;
  void queueEndpointEmail(String modelId, {bool resend = false}) {
    final generation = ++emailGeneration;
    final resendId = resend ? const Uuid().v4() : null;
    ref.read(voiceEndpointEmailProvider.notifier).state = {
      'state': 'waiting_for_endpoint',
      'summary': 'The endpoint will be emailed when its public route is ready.',
    };
    unawaited(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!disposed &&
          generation == emailGeneration &&
          DateTime.now().isBefore(deadline)) {
        final host = ref.read(aiServerProvider.notifier);
        final snapshot = host.snapshot;
        if (snapshot.status != ServerStatus.running ||
            snapshot.selectedModelId != modelId ||
            snapshot.tunnel.status == TunnelStatus.failed) {
          break;
        }
        final url = snapshot.tunnel.publicUrl;
        if (snapshot.tunnel.status == TunnelStatus.running && url != null) {
          ref.read(voiceEndpointEmailProvider.notifier).state = {
            'state': 'sending',
            'summary': 'Sending the endpoint email through HostAny.',
          };
          final result = await emailSender.send(
            publicEndpoint: url,
            localEndpoint: host.apiBaseUrl,
            model: host.selectedModel.name,
            authenticationRequired: snapshot.security.requireApiKey,
            resendId: resendId,
          );
          if (!disposed && generation == emailGeneration) {
            ref.read(voiceEndpointEmailProvider.notifier).state = result;
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!disposed && generation == emailGeneration) {
        ref.read(voiceEndpointEmailProvider.notifier).state = {
          'ok': false,
          'state': 'failed',
          'error': 'public_endpoint_not_ready',
          'summary':
              'Email was not sent because the public model endpoint is unavailable.',
        };
      }
    }());
  }

  final emailedShareActions = <String>{};
  ref.listen(voiceActionsProvider, (_, actions) {
    stopEmail.update();
    for (final action in actions) {
      if (action.tool == 'share_model' &&
          action.state == 'succeeded' &&
          emailedShareActions.add(action.id)) {
        queueEndpointEmail(ref.read(aiServerProvider).selectedModelId);
      }
    }
  });

  Map<String, Object?> setupStatus() {
    if (!requested) {
      return {
        'ok': true,
        'state': 'not_requested',
        'health_verified': false,
        'endpoint_email': ref.read(voiceEndpointEmailProvider),
      };
    }
    if (reusedModelId != null) {
      final host = ref.read(aiServerProvider);
      final active =
          host.status == ServerStatus.running &&
          host.selectedModelId == reusedModelId;
      final endpoint =
          active &&
                  host.tunnel.status == TunnelStatus.running &&
                  host.tunnel.publicUrl != null
              ? '${host.tunnel.publicUrl}/v1'
              : null;
      final failed =
          !active ||
          publicationError != null ||
          host.tunnel.status == TunnelStatus.failed;
      final approvalReady =
          active &&
          endpoint == null &&
          !reuseApproved &&
          DateTime.now().isBefore(reuseExpiresAt!);
      final result = <String, Object?>{
        'ok': !failed,
        'state':
            failed
                ? 'failed'
                : endpoint != null
                ? 'already_running'
                : executingVoicePlan || reuseApproved
                ? 'publishing'
                : approvalReady
                ? 'needs_approval'
                : 'plan_expired',
        'plan_id': reusedPlanId,
        'model':
            host.models.where((m) => m.id == reusedModelId).firstOrNull?.name,
        'model_id': reusedModelId,
        'health_verified': active && reuseVerified,
        'public_endpoint': endpoint,
        'tunnel_state': host.tunnel.status.name,
        'authentication':
            host.security.requireApiKey ? 'Bearer API key' : 'none',
        'approval_ready': approvalReady,
        'reuses_running_model': true,
        'endpoint_email': ref.read(voiceEndpointEmailProvider),
        'summary':
            failed
                ? 'The existing model or its public route needs attention. ${publicationError ?? host.tunnel.lastError ?? ''}'
                : endpoint != null
                ? 'The model is already running. Use its existing public endpoint; no new model setup is needed.'
                : reuseApproved
                ? 'Keeping the existing model running while preparing its public endpoint.'
                : 'The model is already running. Say Go to expose its endpoint without downloading or starting another model.',
        'next_action':
            endpoint != null
                ? 'use_existing_endpoint'
                : executingVoicePlan || reuseApproved
                ? 'check_get_setup_status'
                : approvalReady
                ? 'say_go_to_confirm_model_setup'
                : 'review_in_buildify',
        if (publicationError != null) 'error_code': publicationError,
      };
      ref.read(voiceRunningModelRequestProvider.notifier).state = result;
      return result;
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
      'endpoint_email': ref.read(voiceEndpointEmailProvider),
      'publishing': executingVoicePlan && verified,
      'public_endpoint':
          verified && host.tunnel.publicUrl != null
              ? '${host.tunnel.publicUrl}/v1'
              : null,
      'public_reachability_verified': false,
      'tunnel_state': host.tunnel.status.name,
      if (publicationError != null) 'publication_error': publicationError,
      'authentication': host.security.requireApiKey ? 'Bearer API key' : 'none',
      if (state.failureCode != null) 'error_code': state.failureCode,
      if (state.availableMemoryGiB != null)
        'available_memory_gib': state.availableMemoryGiB,
      if (state.requiredMemoryGiB != null)
        'required_memory_gib': state.requiredMemoryGiB,
      if (state.message != null) 'summary': state.message,
      if (plan != null) 'plan_id': plan.id,
      if (state.candidate != null) 'model': state.candidate!.model.name,
      if (plan != null) 'download_bytes': plan.downloadBytes,
      if (plan != null) 'context_tokens': plan.contextTokens,
      if (plan != null && state.candidate != null)
        'estimated_memory_gib':
            (state.candidate!.estimatedMemoryBytes! +
                const ModelRecommendationService().memoryReserveBytes) /
            1073741824,
      if (state.record?.errorCode != null)
        'error_code': state.record!.errorCode,
      'approval_ready':
          !state.busy &&
          plan != null &&
          state.record == null &&
          DateTime.now().isBefore(plan.expiresAt),
      'approval_location':
          'Say Go to execute this plan and publish an endpoint without API-key authorization',
      'next_action':
          verified
              ? 'use_connection_details_in_buildify'
              : state.busy
              ? 'check_get_setup_status'
              : plan == null
              ? (state.failureCode == 'insufficient_memory'
                  ? 'free_memory_and_retry'
                  : 'resolve_setup_blocker_and_retry')
              : state.record != null
              ? 'review_in_buildify'
              : 'say_go_to_confirm_model_setup',
    };
  }

  Future<void> runVoicePlan() async {
    try {
      final host = ref.read(aiServerProvider.notifier);
      final plan = ref.read(assistantSetupProvider).plan;
      if (plan == null ||
          (host.snapshot.status != ServerStatus.stopped &&
              !plan.stopExisting)) {
        publicationError = 'active_workload';
        return;
      }
      await host.setRequireApiKey(false);
      await ref.read(assistantSetupProvider.notifier).approveAndRun();
      if (disposed ||
          ref.read(assistantSetupProvider).record?.state !=
              ModelOperationState.succeeded) {
        return;
      }
      await host.setModelAccessScope(ModelAccessScope.public);
      if (!await host.startTunnel()) {
        publicationError = 'tunnel_start_failed';
      } else {
        queueEndpointEmail(plan.modelId);
      }
    } catch (_) {
      publicationError = 'execution_or_publication_failed';
    } finally {
      executingVoicePlan = false;
    }
  }

  Future<void> publishRunningModel() async {
    final verifier = ModelEndpointVerifier();
    try {
      final host = ref.read(aiServerProvider.notifier);
      final selected = reusedModelId;
      if (host.snapshot.status != ServerStatus.running ||
          host.snapshot.selectedModelId != selected) {
        throw StateError('Model changed');
      }
      await verifier.verify(
        port: host.snapshot.port,
        apiKey:
            host.snapshot.security.requireApiKey
                ? host.snapshot.security.apiKey
                : null,
      );
      if (disposed) return;
      if (host.snapshot.status != ServerStatus.running ||
          host.snapshot.selectedModelId != selected) {
        throw StateError('Model changed');
      }
      reuseVerified = true;
      await host.setModelAccessScope(ModelAccessScope.public);
      if (host.snapshot.tunnel.status != TunnelStatus.running &&
          host.snapshot.tunnel.status != TunnelStatus.starting &&
          !await host.startTunnel()) {
        publicationError = 'tunnel_start_failed';
      }
      if (publicationError == null && selected != null) {
        queueEndpointEmail(selected);
      }
    } catch (_) {
      publicationError = 'existing_model_publication_failed';
    } finally {
      verifier.close();
      executingVoicePlan = false;
      if (!disposed) setupStatus();
    }
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
    emailGeneration++;
    stopEmail.dispose();
    emailSender.close();
    server?.close();
  });
  Map<String, Object?> requestSetup({String? modelId}) {
    final state = requested ? ref.read(assistantSetupProvider) : null;
    final host = ref.read(aiServerProvider);
    if (!preparing &&
        !executingVoicePlan &&
        state?.busy != true &&
        host.status == ServerStatus.running &&
        (modelId == null || modelId == host.selectedModelId)) {
      if (reusedModelId != host.selectedModelId ||
          reuseExpiresAt == null ||
          !DateTime.now().isBefore(reuseExpiresAt!)) {
        requested = true;
        reusedModelId = host.selectedModelId;
        reusedPlanId = const Uuid().v4();
        reuseExpiresAt = DateTime.now().add(const Duration(minutes: 5));
        reuseApproved = false;
        reuseVerified =
            state?.record?.state == ModelOperationState.succeeded &&
            state?.plan?.modelId == host.selectedModelId;
        publicationError = null;
        if (host.tunnel.status == TunnelStatus.running) {
          queueEndpointEmail(host.selectedModelId);
        }
        final result = setupStatus();
        ref.read(voiceNavigationProvider.notifier).state = VoiceNavigation(
          'actions',
        );
        return result;
      }
      return setupStatus();
    }
    if (preparing ||
        executingVoicePlan ||
        state?.busy == true ||
        (state?.plan != null &&
            state?.record == null &&
            DateTime.now().isBefore(state!.plan!.expiresAt))) {
      return setupStatus();
    }
    requested = true;
    reusedModelId = reusedPlanId = null;
    ref.read(voiceRunningModelRequestProvider.notifier).state = null;
    requestedModelId = modelId;
    emailGeneration++;
    ref.read(voiceEndpointEmailProvider.notifier).state = {
      'state': 'waiting_for_model',
      'summary':
          'This request has not sent an email yet. Email is queued after approval and a ready endpoint.',
    };
    preparing = true;
    preparationError = null;
    publicationError = null;
    ref.read(voiceSetupRequestsProvider.notifier).state++;
    unawaited(prepare());
    return setupStatus();
  }

  server = await StatusProbeServer.start(
    token: token,
    port: session?.port ?? 18791,
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
      if (name == 'email_model_stop_status') {
        return stopEmail.request(normalized['action_id'] as String);
      }
      if (name == 'get_action_status') {
        final id = normalized['action_id'] as String;
        return {
          ...ref.read(voiceActionsProvider.notifier).status(id),
          'action_email': stopEmail.status(id),
        };
      }
      if (name == 'email_model_endpoint') {
        final host = ref.read(aiServerProvider);
        if (host.status != ServerStatus.running ||
            host.tunnel.status != TunnelStatus.running ||
            host.tunnel.publicUrl == null) {
          return {'ok': false, 'error': 'public_endpoint_not_ready'};
        }
        final delivery = ref.read(voiceEndpointEmailProvider);
        final resend = normalized['resend'] == true;
        if (delivery['state'] == 'sending' ||
            delivery['state'] == 'waiting_for_endpoint' ||
            (!resend &&
                delivery['state'] == 'sent' &&
                delivery['public_endpoint'] == host.tunnel.publicUrl)) {
          return delivery;
        }
        if (resend) {
          final now = DateTime.now();
          if (lastExplicitEmailResend != null &&
              now.difference(lastExplicitEmailResend!) <
                  const Duration(minutes: 1)) {
            return {
              'ok': false,
              'error': 'email_resend_cooldown',
              'summary':
                  'Wait one minute before requesting another resend. The model remains running.',
            };
          }
          lastExplicitEmailResend = now;
        }
        queueEndpointEmail(host.selectedModelId, resend: resend);
        return {
          'ok': true,
          'state': 'queued',
          'next_action': 'check_get_setup_status',
        };
      }
      if (name == 'confirm_model_setup') {
        if (reusedModelId != null) {
          if (normalized['plan_id'] != reusedPlanId) {
            return {'ok': false, 'error': 'no_matching_ready_plan'};
          }
          final current = setupStatus();
          if (executingVoicePlan ||
              reuseApproved ||
              current['state'] == 'already_running') {
            return current;
          }
          if (current['approval_ready'] != true) {
            return {'ok': false, 'error': 'running_model_plan_unavailable'};
          }
          reuseApproved = true;
          executingVoicePlan = true;
          unawaited(publishRunningModel());
          return setupStatus();
        }
        final state = ref.read(assistantSetupProvider);
        final plan = state.plan;
        if (!requested ||
            preparing ||
            plan == null ||
            plan.id != normalized['plan_id']) {
          return {'ok': false, 'error': 'no_matching_ready_plan'};
        }
        // Reserve synchronously: duplicate Go requests cannot start another run.
        if (executingVoicePlan || state.busy || state.record != null) {
          return setupStatus();
        }
        if (!DateTime.now().isBefore(plan.expiresAt)) {
          return {'ok': false, 'error': 'plan_expired'};
        }
        executingVoicePlan = true;
        unawaited(runVoicePlan());
        return {
          ...setupStatus(),
          'state': 'starting',
          'next_action': 'check_get_setup_status',
        };
      }
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
