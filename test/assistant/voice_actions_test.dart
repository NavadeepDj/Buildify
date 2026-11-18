import 'dart:async';
import 'package:buildify_flutter/assistant/voice_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local review details stay local and argument order cannot duplicate work',
    () {
      final queue = VoiceActionQueue(execute: (_, __) async => {});
      addTearDown(queue.dispose);
      final first = queue.request(
        'fixture',
        {'name': 'a', 'id': 'b'},
        'Public summary',
        localReview: 'local-secret-command',
      );
      final second = queue.request('fixture', {
        'id': 'b',
        'name': 'a',
      }, 'Public summary');
      expect(first['action_id'], second['action_id']);
      expect(first.toString(), isNot(contains('local-secret-command')));
    },
  );
  test(
    'requests are deduplicated and cannot execute before local approval',
    () async {
      var calls = 0;
      final queue = VoiceActionQueue(
        execute: (_, __) async {
          calls++;
          return {'ok': true};
        },
      );
      addTearDown(queue.dispose);
      final first = queue.request('stop_model', {}, 'Stop model');
      final second = queue.request('stop_model', {}, 'Stop model');
      expect(first['action_id'], second['action_id']);
      expect(calls, 0);
      await queue.approve(first['action_id'] as String);
      await queue.approve(first['action_id'] as String);
      expect(calls, 1);
      expect(queue.status(first['action_id'] as String)['state'], 'succeeded');
    },
  );
  test('rejected and expired actions never execute', () async {
    var now = DateTime.utc(2026, 11, 15);
    var calls = 0;
    final queue = VoiceActionQueue(
      clock: () => now,
      execute: (_, __) async {
        calls++;
        return {};
      },
    );
    addTearDown(queue.dispose);
    final rejected = queue.request('delete_model', {
      'model_id': 'fixture',
    }, 'Delete fixture');
    queue.reject(rejected['action_id'] as String);
    await queue.approve(rejected['action_id'] as String);
    final expired = queue.request('delete_project', {
      'project_id': 'fixture',
    }, 'Delete fixture');
    now = now.add(const Duration(minutes: 6));
    await queue.approve(expired['action_id'] as String);
    expect(calls, 0);
    expect(queue.status(expired['action_id'] as String)['state'], 'expired');
  });
  test(
    'conflicting work stays pending, and failures do not leak exception text',
    () async {
      final done = Completer<Map<String, Object?>>();
      final queue = VoiceActionQueue(
        execute:
            (name, _) =>
                name == 'first'
                    ? done.future
                    : throw StateError('secret-path-api-key'),
      );
      addTearDown(queue.dispose);
      final first = queue.request('first', {}, 'First');
      final second = queue.request('second', {}, 'Second');
      final running = queue.approve(first['action_id'] as String);
      await queue.approve(second['action_id'] as String);
      expect(
        queue.status(second['action_id'] as String)['state'],
        'needs_approval',
      );
      done.complete({'ok': true});
      await running;
      await queue.approve(second['action_id'] as String);
      expect(
        queue.status(second['action_id'] as String).toString(),
        isNot(contains('secret-path-api-key')),
      );
      expect(queue.status(second['action_id'] as String)['state'], 'failed');
    },
  );
  test('review queue is bounded and rejects new requests when full', () {
    final queue = VoiceActionQueue(execute: (_, __) async => {});
    addTearDown(queue.dispose);
    for (var i = 0; i < 8; i++) {
      queue.request('delete_model', {'model_id': '$i'}, 'Delete fixture');
    }
    expect(
      queue.request('delete_model', {
        'model_id': 'overflow',
      }, 'Delete fixture')['ok'],
      false,
    );
    expect(queue.state.length, 8);
  });
}
