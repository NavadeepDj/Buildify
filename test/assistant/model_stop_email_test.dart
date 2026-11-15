import 'dart:async';
import 'dart:convert';

import 'package:buildify_flutter/assistant/model_endpoint_email.dart';
import 'package:buildify_flutter/assistant/model_stop_email.dart';
import 'package:buildify_flutter/assistant/voice_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

VoiceAction action(
  String id,
  String state, {
  String tool = 'stop_model',
  Map<String, Object?>? result,
}) => VoiceAction(
  id: id,
  tool: tool,
  arguments: const {},
  description: 'Stop fixture',
  createdAt: DateTime.utc(2026),
  state: state,
  result: result,
);
const stopped = <String, Object?>{
  'ok': true,
  'state': 'stopped',
  'model_name': 'Fixture',
  'stopped_at': '2026-11-15T12:18:00Z',
};

void main() {
  test(
    'queued notification waits for proof and deduplicates across updates',
    () async {
      var current = action('one', 'needs_approval');
      var sends = 0;
      final receipt = Completer<Map<String, Object?>>();
      final notifier = ModelStopEmail(
        findAction: (id) => id == current.id ? current : null,
        deliver: (_) {
          sends++;
          return receipt.future;
        },
      );
      expect(notifier.request('missing')['error'], 'unknown_stop_action');
      expect(notifier.request('one')['state'], 'waiting_for_action');
      expect(sends, 0);
      current = action('one', 'running');
      notifier.update();
      expect(sends, 0);
      current = action('one', 'succeeded', result: stopped);
      // No polling or active call is required to initiate delivery.
      notifier.update();
      notifier.request('one');
      notifier.update();
      expect(sends, 1);
      expect(notifier.status('one')['state'], 'sending');
      receipt.complete({'ok': true, 'state': 'sent'});
      await Future<void>.delayed(Duration.zero);
      expect(notifier.request('one')['state'], 'sent');
      expect(sends, 1);
      notifier.dispose();
    },
  );

  test(
    'failed, rejected, expired, and unverified stops cannot send success',
    () {
      for (final state in ['failed', 'rejected', 'expired', 'succeeded']) {
        final current = action(
          'one',
          state,
          result: {'ok': true, 'state': 'running'},
        );
        final notifier = ModelStopEmail(
          findAction: (_) => current,
          deliver: (_) => throw StateError('Must not send'),
        );
        expect(notifier.request('one')['error'], 'stop_not_verified');
        notifier.dispose();
      }
      final notifier = ModelStopEmail(
        findAction:
            (_) => action(
              'project',
              'succeeded',
              tool: 'stop_project',
              result: stopped,
            ),
        deliver: (_) => throw StateError('Must not send'),
      );
      expect(notifier.request('project')['error'], 'unknown_stop_action');
      notifier.dispose();
    },
  );

  test(
    'provider errors remain failures, with no automatic repeated sends',
    () async {
      var sends = 0;
      final notifier = ModelStopEmail(
        findAction: (_) => action('one', 'succeeded', result: stopped),
        deliver: (_) async {
          sends++;
          throw StateError('private detail');
        },
      );
      notifier.request('one');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.request('one')['state'], 'failed');
      expect(
        notifier.status('one').toString(),
        isNot(contains('private detail')),
      );
      expect(sends, 1);
      notifier.dispose();
    },
  );

  test(
    'stop sender uses fixed recipient, distinct receipt, and idempotency',
    () async {
      final requests = <http.Request>[];
      final sender = ModelEndpointEmailSender(
        configuration:
            () async => {
              'BUILDIFY_RESEND_API_KEY': 'test-secret',
              'BUILDIFY_ENDPOINT_EMAIL_TO': 'owner@example.com',
              'BUILDIFY_EMAIL_FROM': 'Buildify <sender@example.com>',
            },
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'id': 'mail-${requests.length}'}),
            200,
          );
        }),
      );
      final receipt = await sender.sendStopped(
        actionId: 'one',
        model: 'Fixture',
        stoppedAt: stopped['stopped_at'] as String,
      );
      await sender.sendStopped(
        actionId: 'one',
        model: 'Fixture',
        stoppedAt: stopped['stopped_at'] as String,
      );
      expect(requests.length, 1);
      expect(receipt['state'], 'sent');
      expect(receipt['action_id'], 'one');
      expect(receipt.containsKey('public_endpoint'), false);
      expect(receipt.toString(), isNot(contains('test-secret')));
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['to'], ['owner@example.com']);
      expect(body['text'], contains('2026-11-15T12:18:00Z'));
      expect(body['text'], isNot(contains('model is running')));
      await sender.sendStopped(
        actionId: 'two',
        model: 'Fixture',
        stoppedAt: stopped['stopped_at'] as String,
      );
      expect(requests.length, 2);
      expect(
        requests[0].headers['idempotency-key'],
        isNot(requests[1].headers['idempotency-key']),
      );
      final endpoint = await sender.send(
        publicEndpoint: 'https://fixture.example',
        localEndpoint: 'http://localhost:8080',
        model: 'Fixture',
        authenticationRequired: false,
      );
      expect(endpoint['public_endpoint'], 'https://fixture.example');
      expect(
        (jsonDecode(requests.last.body) as Map)['subject'],
        'Your Buildify model endpoint',
      );
      sender.close();
    },
  );

  test('missing credentials and rejected mail never report sent', () async {
    final absent = ModelEndpointEmailSender(configuration: () async => {});
    expect(
      (await absent.sendStopped(
        actionId: 'one',
        model: 'Fixture',
        stoppedAt: 'now',
      ))['state'],
      'not_configured',
    );
    absent.close();
    final rejected = ModelEndpointEmailSender(
      configuration:
          () async => {
            'BUILDIFY_RESEND_API_KEY': 'secret',
            'BUILDIFY_ENDPOINT_EMAIL_TO': 'owner@example.com',
          },
      client: MockClient((_) async => http.Response('private error', 403)),
    );
    final result = await rejected.sendStopped(
      actionId: 'one',
      model: 'Fixture',
      stoppedAt: 'now',
    );
    expect(result['state'], 'failed');
    expect(result.toString(), isNot(contains('private error')));
    rejected.close();
  });
}
