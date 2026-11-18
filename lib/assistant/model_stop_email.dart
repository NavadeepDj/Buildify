import 'dart:async';

import 'voice_actions.dart';

/// Owner-requested notifications outlive a voice call, while the host stays open.
/// Completion evidence comes only from the action queue, never voice arguments.
class ModelStopEmail {
  ModelStopEmail({required this.findAction, required this.deliver});

  final VoiceAction? Function(String id) findAction;
  final Future<Map<String, Object?>> Function(VoiceAction action) deliver;
  final _receipts = <String, Map<String, Object?>>{};
  bool _disposed = false;

  Map<String, Object?> status(String id) =>
      _receipts[id] ?? const {'state': 'not_requested'};

  Map<String, Object?> request(String id) {
    final action = findAction(id);
    if (action == null || action.tool != 'stop_model') {
      return {'ok': false, 'error': 'unknown_stop_action'};
    }
    if (_receipts.containsKey(id)) return status(id);
    if (_receipts.length >= 64) {
      return {'ok': false, 'error': 'notification_limit_reached'};
    }
    _receipts[id] = {
      'ok': true,
      'state': 'waiting_for_action',
      'action_id': id,
    };
    update();
    return status(id);
  }

  void update() {
    if (_disposed) return;
    for (final id in _receipts.keys.toList()) {
      if (_receipts[id]?['state'] != 'waiting_for_action') continue;
      final action = findAction(id);
      if (action != null &&
          {'needs_approval', 'running'}.contains(action.state)) {
        continue;
      }
      final result = action?.result;
      if (action?.state != 'succeeded' ||
          result?['ok'] != true ||
          result?['state'] != 'stopped' ||
          result?['model_name'] is! String ||
          result?['stopped_at'] is! String) {
        _receipts[id] = {
          'ok': false,
          'state': 'failed',
          'action_id': id,
          'error': 'stop_not_verified',
          'summary':
              'No stop confirmation email was sent because the stop did not return verified completion details.',
        };
        continue;
      }
      _receipts[id] = {'ok': true, 'state': 'sending', 'action_id': id};
      unawaited(_send(action!));
    }
  }

  Future<void> _send(VoiceAction action) async {
    Map<String, Object?> receipt;
    try {
      receipt = await deliver(action);
    } catch (_) {
      receipt = {
        'ok': false,
        'state': 'failed',
        'error': 'status_email_failed',
      };
    }
    if (!_disposed) _receipts[action.id] = {...receipt, 'action_id': action.id};
  }

  void dispose() => _disposed = true;
}
