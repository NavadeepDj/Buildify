import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/embedded_backend.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import '../services/git_service.dart';
import '../services/subdomain.dart';
import 'model_endpoint_verifier.dart';
import 'setup_controller.dart';
import 'voice_actions.dart';
import 'voice_tool_specs.dart';

class VoiceNavigation {
  VoiceNavigation(this.page, [this.projectId]);
  final String page;
  final String? projectId;
}

final voiceNavigationProvider = StateProvider<VoiceNavigation?>((ref) => null);
final voiceToolRuntimeProvider = Provider((ref) => VoiceToolRuntime(ref));
final voiceActionsProvider =
    StateNotifierProvider<VoiceActionQueue, List<VoiceAction>>((ref) {
      return VoiceActionQueue(
        execute:
            (name, args) =>
                ref.read(voiceToolRuntimeProvider).execute(name, args),
      );
    });

class VoiceToolRuntime {
  VoiceToolRuntime(this.ref);
  final Ref ref;
  AiServerController get host => ref.read(aiServerProvider.notifier);
  EmbeddedBackendService get backend => ref.read(embeddedBackendProvider);

  Future<void> _ready() async {
    final controller = host;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (controller.snapshot.models.isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  BackendProject _project(Map<String, Object?> args) =>
      backend.state.projects.firstWhere((p) => p.id == args['project_id']);
  void _model(Map<String, Object?> args) {
    if (!host.snapshot.models.any((m) => m.id == args['model_id'])) {
      throw StateError('Unknown model');
    }
  }

  Map<String, Object?> _projectJson(BackendProject project) => {
    'project_id': project.id,
    'name': project.name,
    'type': project.repoProvider,
    'app_reports_live': project.isLive,
    'local_port': project.port,
    'public_route_status': project.liveUrlStatus,
    'public_url': project.liveUrl,
    'hosting_mode': project.hostingMode.name,
    'environment_names': project.envVars.keys.toList(),
    'has_start_or_build_command': project.buildCommand.isNotEmpty,
    'health_verified': false,
  };
  String _projectRevision(BackendProject project) {
    final keys = project.envVars.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              project.id,
              project.localPath,
              project.repoProvider,
              project.buildCommand,
              project.baseDir,
              project.publishDir,
              project.port,
              {for (final key in keys) key: project.envVars[key]},
            ]),
          ),
        )
        .toString();
  }

  String _redact(String text) {
    final secrets =
        <String>[
            host.snapshot.security.apiKey,
            for (final project in backend.state.projects)
              ...project.envVars.values,
          ].where((s) => s.isNotEmpty).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in secrets) {
      text = text.replaceAll(secret, '[redacted]');
    }
    text = text.replaceAll(
      RegExp(r'bearer\s+\S+', caseSensitive: false),
      'Bearer [redacted]',
    );
    text = text.replaceAll(
      RegExp(r'(?:sk-|bn-|hf_)[A-Za-z0-9_-]{8,}'),
      '[redacted]',
    );
    text = text.replaceAll(RegExp(r'https?://\S+'), '[url]');
    text = text.replaceAll(RegExp(r'[A-Za-z]:[\\/][^\r\n]*'), '[local path]');
    return text.length > 400 ? text.substring(0, 400) : text;
  }

  Future<Map<String, Object?>> invoke(
    String name,
    Map<String, Object?> args,
  ) async {
    final spec = voiceToolSpecs.where((s) => s.name == name).firstOrNull;
    if (spec == null || !spec.accepts(args)) {
      return {'ok': false, 'error': 'invalid_tool_or_arguments'};
    }
    try {
      if (name == 'confirm_model_action') {
        final id = args['action_id'] as String;
        final action =
            ref.read(voiceActionsProvider).where((a) => a.id == id).firstOrNull;
        const allowed = {
          'stop_model',
          'share_model',
          'make_model_private',
          'select_model',
          'download_model',
          'cancel_model_download',
          'cancel_model_setup',
        };
        if (action == null || !allowed.contains(action.tool)) {
          return {
            'ok': false,
            'error': 'model_action_not_eligible_for_voice_confirmation',
          };
        }
        unawaited(ref.read(voiceActionsProvider.notifier).approve(id));
        return ref.read(voiceActionsProvider.notifier).status(id);
      }
      if (name == 'list_capabilities') {
        return {
          'ok': true,
          'tools': voiceToolSpecs.map((s) => s.toJson()).toList(),
          'policy':
              'Paired-owner voice approval runs prepared model plans and eligible reversible model actions. Project actions and deletions still require local review. Single paired demo host only.',
        };
      }
      if (name == 'get_host_status') {
        final observation =
            (await ref
                .read(assistantInspectionToolsProvider)
                .invoke('get_runtime_state')).data;
        return {
          'ok': observation != null,
          'source': 'buildify_live_app',
          'observed_at': DateTime.now().toUtc().toIso8601String(),
          ...?observation,
        };
      }
      if (name == 'list_actions') {
        return {
          'ok': true,
          'actions':
              ref
                  .read(voiceActionsProvider)
                  .reversed
                  .take(16)
                  .map((a) => a.toJson())
                  .toList(),
        };
      }
      if (name == 'get_action_status') {
        return ref
            .read(voiceActionsProvider.notifier)
            .status(args['action_id'] as String);
      }
      if (name == 'get_device_info') {
        return (await ref
            .read(assistantInspectionToolsProvider)
            .invoke('get_device_capabilities')).toJson();
      }
      if (name == 'list_models' ||
          name.startsWith('get_model') ||
          name.contains('model') ||
          name == 'set_generation_settings') {
        await _ready();
      }
      if (name == 'list_models') {
        return {
          'ok': true,
          'models': [
            for (final model in host.snapshot.models)
              {
                'model_id': model.id,
                'name': model.name,
                'size': model.sizeLabel,
                'download_state':
                    host.snapshot.downloads[model.id]?.status.name ??
                    'notDownloaded',
                'download_progress':
                    host.snapshot.downloads[model.id]?.progress ?? 0,
                'selected': host.snapshot.selectedModelId == model.id,
              },
          ],
        };
      }
      if (name == 'get_model_connection') {
        return {
          'ok': true,
          'state': host.snapshot.status.name,
          'model_id': host.snapshot.selectedModelId,
          'local_base_url': '${host.apiBaseUrl}/v1',
          'public_base_url':
              host.snapshot.tunnel.publicUrl == null
                  ? null
                  : '${host.snapshot.tunnel.publicUrl}/v1',
          'authentication_required': host.snapshot.security.requireApiKey,
          'health_verified': false,
          'scope': host.modelAccessScope.name,
          'tunnel_state': host.snapshot.tunnel.status.name,
        };
      }
      if (name == 'get_model_diagnostics') {
        return {
          'ok': true,
          'state': host.snapshot.status.name,
          'logs':
              host.snapshot.logs.reversed
                  .take(12)
                  .map((l) => _redact(l.message))
                  .toList(),
          'cause_confirmed': false,
        };
      }
      if (name.contains('project')) await backend.ready;
      if (name == 'list_projects') {
        return {
          'ok': true,
          'projects': backend.state.projects.map(_projectJson).toList(),
        };
      }
      if (name == 'get_project') {
        return {'ok': true, ..._projectJson(_project(args))};
      }
      if (name == 'get_project_diagnostics') {
        final project = _project(args);
        return {
          'ok': true,
          ..._projectJson(project),
          'cause_confirmed': false,
          'logs':
              backend.state.logs
                  .where((l) => l.projectId == project.id)
                  .toList()
                  .reversed
                  .take(12)
                  .map((l) => _redact(l.message))
                  .toList(),
        };
      }
      if (args.containsKey('model_id')) _model(args);
      if (args.containsKey('project_id')) _project(args);
      if (name == 'import_static_project') {
        final url = Uri.tryParse(args['repo_url'] as String);
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.userInfo.isNotEmpty ||
            url.hasQuery ||
            url.hasFragment ||
            url.pathSegments.length != 2 ||
            url.pathSegments.any(
              (s) =>
                  !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(s) ||
                  s == '.' ||
                  s == '..',
            )) {
          return {
            'ok': false,
            'error': 'use_public_github_owner_repository_url',
          };
        }
      }
      if (name == 'set_project_subdomain' &&
          validateSubdomain(args['subdomain'] as String) != null) {
        return {'ok': false, 'error': 'invalid_or_reserved_subdomain'};
      }
      final automatic = name == 'verify_model' || name == 'verify_project';
      final description =
          '${spec.description}\n${args.entries.map((e) => '${e.key}: ${e.value}').join('\n')}';
      final actionArguments = Map<String, Object?>.from(args);
      String localReview = description;
      if (args.containsKey('project_id')) {
        final project = _project(args);
        actionArguments['_project_revision'] = _projectRevision(project);
        localReview =
            '$description\nProject: ${project.name}\nRuntime: ${project.repoProvider}\nSaved build/start command: ${project.buildCommand.isEmpty ? '(none)' : project.buildCommand}\nHosting mode: ${project.hostingMode.name}\nStarting can interrupt the active project and expose its saved public route.';
      }
      if (args.containsKey('model_id')) {
        final model = host.snapshot.models.firstWhere(
          (m) => m.id == args['model_id'],
        );
        actionArguments['_model_revision'] =
            '${model.fileName}|${model.downloadUrl}';
        localReview =
            '$description\nModel: ${model.name}\nDownload size: ${model.sizeLabel}';
      }
      final knownIds = ref.read(voiceActionsProvider).map((a) => a.id).toSet();
      final action = ref
          .read(voiceActionsProvider.notifier)
          .request(
            name,
            actionArguments,
            description,
            automatic: automatic,
            localReview: localReview,
          );
      if (!automatic &&
          action['state'] == 'needs_approval' &&
          !knownIds.contains(action['action_id'])) {
        ref.read(voiceNavigationProvider.notifier).state = VoiceNavigation(
          'actions',
        );
      }
      return {
        'ok': action['ok'] != false,
        ...action,
        'next_action':
            automatic ? 'check_get_action_status' : 'approve_in_buildify',
      };
    } catch (_) {
      return {
        'ok': false,
        'error': 'resource_unavailable',
        'next_action': 'check_local_app',
      };
    }
  }

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args,
  ) async {
    if (name != 'cancel_model_setup' &&
        ref.read(assistantSetupProvider).busy &&
        (name.contains('model') || name.startsWith('set_'))) {
      return {'ok': false, 'error': 'model_setup_active'};
    }
    // Re-resolve IDs after local approval; remote input never supplies paths,
    // shell commands, API keys or environment values.
    if (args.containsKey('model_id')) {
      _model(args);
      final model = host.snapshot.models.firstWhere(
        (m) => m.id == args['model_id'],
      );
      if (args['_model_revision'] != null &&
          args['_model_revision'] != '${model.fileName}|${model.downloadUrl}') {
        return {'ok': false, 'error': 'model_changed_request_new_approval'};
      }
    }
    if (args.containsKey('project_id')) {
      final project = _project(args);
      if (args['_project_revision'] != null &&
          args['_project_revision'] != _projectRevision(project)) {
        return {
          'ok': false,
          'error': 'project_settings_changed_request_new_approval',
        };
      }
    }
    switch (name) {
      case 'verify_model':
        if (host.snapshot.status != ServerStatus.running) {
          return {
            'ok': false,
            'error': 'model_not_running',
            'health_verified': false,
          };
        }
        final modelId = host.snapshot.selectedModelId;
        final verifier = ModelEndpointVerifier();
        try {
          final duration = await verifier.verify(
            port: host.snapshot.port,
            apiKey:
                host.snapshot.security.requireApiKey
                    ? host.snapshot.security.apiKey
                    : null,
          );
          return {
            'ok': true,
            'health_verified':
                host.snapshot.status == ServerStatus.running &&
                host.snapshot.selectedModelId == modelId,
            'model_id': modelId,
            'inference_ms': duration.inMilliseconds,
            'scope': 'local',
          };
        } finally {
          verifier.close();
        }
      case 'stop_model':
        final stoppedModel = host.selectedModel;
        await host.stopServer();
        return {
          'ok': host.snapshot.status == ServerStatus.stopped,
          'state': host.snapshot.status.name,
          'model_id': stoppedModel.id,
          'model_name': stoppedModel.name,
          if (host.snapshot.status == ServerStatus.stopped)
            'stopped_at': DateTime.now().toUtc().toIso8601String(),
        };
      case 'cancel_model_setup':
        await ref.read(assistantSetupProvider.notifier).cancel();
        return {'ok': true, 'state': 'cancellation_requested'};
      case 'select_model':
        host.selectModel(args['model_id'] as String);
        return {
          'ok': host.snapshot.selectedModelId == args['model_id'],
          'model_id': host.snapshot.selectedModelId,
        };
      case 'download_model':
        await host.downloadModel(args['model_id'] as String);
        return {
          'ok':
              host.snapshot.downloads[args['model_id']]?.status ==
              ModelDownloadStatus.downloaded,
          'artifact_verified': false,
        };
      case 'cancel_model_download':
        await host.cancelDownload(args['model_id'] as String);
        return {
          'ok': true,
          'state': host.snapshot.downloads[args['model_id']]?.status.name,
        };
      case 'delete_model':
        final artifact = await host.modelArtifactForAssistant(
          args['model_id'] as String,
        );
        await host.deleteModel(args['model_id'] as String);
        return {'ok': !await artifact.exists()};
      case 'refresh_model_catalog':
        await host.refreshCatalog();
        return {
          'ok': host.snapshot.models.isNotEmpty,
          'model_count': host.snapshot.models.length,
        };
      case 'set_temperature':
      case 'set_token_limit':
      case 'set_low_power':
        if (args['low_power'] is bool) {
          host.setLowPowerMode(args['low_power'] as bool);
        }
        if (args['temperature'] is num) {
          host.setTemperature((args['temperature'] as num).toDouble());
        }
        if (args['token_limit'] is num) {
          host.setTokenLimit((args['token_limit'] as num).toDouble());
        }
        return {
          'ok': true,
          'temperature': host.snapshot.temperature,
          'token_limit': host.snapshot.tokenLimit,
          'low_power': host.snapshot.lowPowerMode,
        };
      case 'share_model':
        if (host.snapshot.status != ServerStatus.running) {
          return {'ok': false, 'error': 'start_model_first'};
        }
        await host.setModelAccessScope(ModelAccessScope.public);
        final started = await host.startTunnel();
        return {
          'ok': started,
          'tunnel_state': host.snapshot.tunnel.status.name,
          'public_reachability_verified': false,
        };
      case 'make_model_private':
        await host.setModelAccessScope(ModelAccessScope.deviceNetwork);
        await host.stopTunnel();
        host.stopNamedTunnel();
        return {'ok': true, 'scope': host.modelAccessScope.name};
      case 'start_project':
      case 'restart_project':
        final project = _project(args);
        await backend.startSession(projectId: project.id);
        final checked = await _verifyProject(project);
        return {
          ...checked,
          'project_id': project.id,
          'public_reachability_verified': false,
        };
      case 'stop_project':
        final project = _project(args);
        final active = backend.state.activeSession;
        if (active?.projectId == project.id) {
          await backend.stopSession(sessionId: active!.id);
        }
        return {'ok': backend.state.activeSession?.projectId != project.id};
      case 'delete_project':
        await backend.deleteProject(args['project_id'] as String);
        return {
          'ok': !backend.state.projects.any((p) => p.id == args['project_id']),
        };
      case 'verify_project':
        return _verifyProject(_project(args));
      case 'import_static_project':
        final project = await backend.createProject(
          name: args['name'] as String,
          sourceType: 'Static',
          customUrl: args['repo_url'] as String,
        );
        await GitService.cloneRepository(
          repoUrl: args['repo_url'] as String,
          localPath: project.localPath,
        );
        return {
          'ok': true,
          'project_id': project.id,
          'state': 'imported',
          'deployed': false,
          'next_action': 'review_files_and_request_start_project',
        };
      case 'set_project_subdomain':
        await backend.liveUrls.assign(
          args['project_id'] as String,
          custom: args['subdomain'] as String,
        );
        return {'ok': true, ..._projectJson(_project(args))};
      case 'open_project_wizard':
        ref.read(voiceNavigationProvider.notifier).state = VoiceNavigation(
          'wizard',
        );
        return {'ok': true, 'state': 'needs_local_input'};
      case 'open_project_settings':
        ref.read(voiceNavigationProvider.notifier).state = VoiceNavigation(
          'project',
          args['project_id'] as String,
        );
        return {'ok': true, 'state': 'needs_local_input'};
      case 'open_project_environment':
        ref.read(voiceNavigationProvider.notifier).state = VoiceNavigation(
          'environment',
          args['project_id'] as String,
        );
        return {'ok': true, 'state': 'needs_local_secret_input'};
      default:
        return {'ok': false, 'error': 'unsupported_action'};
    }
  }

  Future<Map<String, Object?>> _verifyProject(BackendProject project) async {
    if (backend.state.activeSession?.projectId != project.id) {
      return {
        'ok': false,
        'error': 'project_not_running',
        'health_verified': false,
      };
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${project.port}/'),
      );
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final healthy = response.statusCode >= 200 && response.statusCode < 300;
      return {
        'ok': healthy,
        'http_status': response.statusCode,
        'health_verified': healthy,
        'scope': 'local_http_root',
      };
    } finally {
      client.close(force: true);
    }
  }
}
