import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('buildify.ai/server');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'native bridge forwards explicit approved context and rejects invalid sizes',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect((call.arguments as Map)['contextTokens'], 2048);
            return {'ok': true, 'status': 'starting'};
          });
      const bridge = NativeServerBridge();
      expect(
        (await bridge.startServer(
          modelPath: 'synthetic.gguf',
          port: 8080,
          contextTokens: 2048,
        )).ok,
        isTrue,
      );
      expect(
        (await bridge.startServer(
          modelPath: 'synthetic.gguf',
          port: 8080,
          contextTokens: 100000,
        )).ok,
        isFalse,
      );
      expect(calls, 1);
    },
  );
}
