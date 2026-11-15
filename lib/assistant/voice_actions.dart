import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class VoiceAction {
  const VoiceAction({
    required this.id,
    required this.tool,
    required this.arguments,
    required this.description,
    required this.createdAt,
    this.state = 'needs_approval',
    this.result,
    this.localReview,
  });
  final String id, tool, description, state;
  final Map<String, Object?> arguments;
  final DateTime createdAt;
  final Map<String, Object?>? result;
  final String? localReview;
  VoiceAction copy(String state, [Map<String, Object?>? result]) => VoiceAction(
    id: id,
    tool: tool,
    arguments: arguments,
    description: description,
    createdAt: createdAt,
    state: state,
    result: result ?? this.result,
    localReview: localReview,
  );
  Map<String, Object?> toJson() => {
    'action_id': id,
    'tool': tool,
    'state': state,
    'created_at': createdAt.toUtc().toIso8601String(),
    'summary': description,
    if (result != null) 'result': result,
  };
}

/// Local UI and the paired-owner confirmation tool can approve eligible actions.
class VoiceActionQueue extends StateNotifier<List<VoiceAction>> {
  VoiceActionQueue({required this.execute, DateTime Function()? clock})
    : clock = clock ?? DateTime.now,
      super(const []);
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)
  execute;
  final DateTime Function() clock;
  bool _running = false;
  bool _closed = false;
  Map<String, Object?> request(
    String tool,
    Map<String, Object?> arguments,
    String description, {
    bool automatic = false,
    String? localReview,
  }) {
    if (automatic && _running) {
      return {'ok': false, 'error': 'host_busy_retry_after_active_action'};
    }
    String signatureOf(Map<String, Object?> value) {
      final keys = value.keys.toList()..sort();
      return jsonEncode({for (final key in keys) key: value[key]});
    }

    final signature = signatureOf(arguments);
    for (final action in state.reversed) {
      if (action.tool == tool &&
          signatureOf(action.arguments) == signature &&
          clock().difference(action.createdAt) < const Duration(minutes: 5) &&
          {'needs_approval', 'running'}.contains(action.state)) {
        return action.toJson();
      }
    }
    if (state.where((a) => a.state == 'needs_approval').length >= 8) {
      return {'ok': false, 'error': 'review_pending_actions_first'};
    }
    final action = VoiceAction(
      id: const Uuid().v4(),
      tool: tool,
      arguments: Map.unmodifiable(arguments),
      description: description,
      createdAt: clock(),
      localReview: localReview,
    );
    state = [
      ...state
          .where((a) => a.state == 'needs_approval' || a.state == 'running')
          .take(16),
      ...state
          .where((a) => a.state != 'needs_approval' && a.state != 'running')
          .toList()
          .reversed
          .take(15)
          .toList()
          .reversed,
      action,
    ];
    if (automatic) unawaited(approve(action.id));
    return state.firstWhere((a) => a.id == action.id).toJson();
  }

  Map<String, Object?> status(String id) {
    final found = state.where((a) => a.id == id).firstOrNull;
    return found?.toJson() ?? {'ok': false, 'error': 'unknown_action'};
  }

  void _set(String id, String value, [Map<String, Object?>? result]) {
    if (!_closed) {
      state = [for (final a in state) a.id == id ? a.copy(value, result) : a];
    }
  }

  Future<void> approve(String id) async {
    final action = state.where((a) => a.id == id).firstOrNull;
    if (action == null || action.state != 'needs_approval' || _running) return;
    if (clock().difference(action.createdAt) >= const Duration(minutes: 5)) {
      _set(id, 'expired');
      return;
    }
    _running = true;
    _set(id, 'running');
    try {
      final result = await execute(action.tool, action.arguments);
      _set(id, result['ok'] == false ? 'failed' : 'succeeded', result);
    } catch (_) {
      // Never send raw native exceptions, filesystem paths or credentials.
      _set(id, 'failed', {
        'ok': false,
        'error': 'operation_failed',
        'next_action': 'review_local_app_logs',
      });
    } finally {
      _running = false;
    }
  }

  void reject(String id) {
    final action = state.where((a) => a.id == id).firstOrNull;
    if (action?.state == 'needs_approval') _set(id, 'rejected');
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
