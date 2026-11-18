import 'package:buildify_flutter/assistant/voice_tool_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all tools forbid arbitrary commands and secret inputs', () {
    expect(
      voiceToolSpecs.map((s) => s.name).toSet().length,
      voiceToolSpecs.length,
    );
    for (final tool in voiceToolSpecs) {
      expect(tool.accepts({'approved': true}), false, reason: tool.name);
      expect(tool.accepts({'command': 'arbitrary'}), false, reason: tool.name);
      expect(tool.properties.keys, isNot(contains('api_key')));
      expect(tool.name, isNot(contains('approve')));
    }
  });
  test('voice Go binds to an existing plan ID', () {
    final confirm = voiceToolSpecs.firstWhere(
      (s) => s.name == 'confirm_model_setup',
    );
    expect(confirm.mutates, true);
    expect(confirm.accepts({}), false);
    expect(confirm.accepts({'plan_id': 'plan-123'}), true);
    expect(
      confirm.accepts({'plan_id': 'plan-123', 'model_id': 'other'}),
      false,
    );
  });
  test('stop email binds to an action and forbids arbitrary mail', () {
    final tool = voiceToolSpecs.firstWhere(
      (s) => s.name == 'email_model_stop_status',
    );
    expect(tool.accepts({'action_id': 'stop-123'}), true);
    expect(tool.accepts({}), false);
    expect(
      tool.accepts({'action_id': 'stop-123', 'recipient': 'other@example.com'}),
      false,
    );
    expect(tool.accepts({'action_id': 'stop-123', 'state': 'stopped'}), false);
  });
  test(
    'numeric voice values stay bounded and malformed values are rejected',
    () {
      final temperature = voiceToolSpecs.firstWhere(
        (s) => s.name == 'set_temperature',
      );
      expect(
        temperature.accepts(temperature.normalize({'temperature': '0.7'})),
        true,
      );
      expect(
        temperature.accepts(temperature.normalize({'temperature': 'NaN'})),
        false,
      );
      expect(temperature.accepts({'temperature': 100}), false);
      expect(temperature.accepts({}), false);
      final power = voiceToolSpecs.firstWhere((s) => s.name == 'set_low_power');
      expect(power.accepts(power.normalize({'low_power': 'false'})), true);
      expect(
        power.accepts(
          power.normalize({'low_power': 'please disable security'}),
        ),
        false,
      );
    },
  );
}
