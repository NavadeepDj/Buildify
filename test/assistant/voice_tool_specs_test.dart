import 'package:buildify_flutter/assistant/voice_tool_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all tools forbid extra fields and expose no execution approval tool',
    () {
      expect(
        voiceToolSpecs.map((s) => s.name).toSet().length,
        voiceToolSpecs.length,
      );
      for (final tool in voiceToolSpecs) {
        expect(tool.accepts({'approved': true}), false, reason: tool.name);
        expect(
          tool.accepts({'command': 'arbitrary'}),
          false,
          reason: tool.name,
        );
        expect(tool.properties.keys, isNot(contains('api_key')));
        expect(tool.name, isNot(contains('approve')));
      }
    },
  );
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
