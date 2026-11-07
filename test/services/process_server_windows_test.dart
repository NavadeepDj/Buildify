import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/services/process_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Windows project commands withhold inherited secrets and stop the listening child',
    () async {
      final root = await Directory.systemTemp.createTemp('hostany project ');
      final dart = p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          '../../../dart-sdk/bin/dart.exe',
        ),
      );
      expect(File(dart).existsSync(), true);
      final fixture = File(p.join(root.path, 'server.dart'));
      await fixture.writeAsString('''
import 'dart:io';
import 'dart:convert';
Future<void> main() async {
 final server = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(Platform.environment['PORT']!));
 print('READY');
 await for (final request in server) {
   request.response.write(jsonEncode(Platform.environment.keys.toList()));
   await request.response.close();
 }
}
''');
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final ready = Completer<void>();
      final messages = <String>[];
      final server = ProcessServer(
        command: '"$dart" "${fixture.path}"',
        workingDirectory: root.path,
        port: port,
        onLog: (message, {isError = false}) {
          messages.add(message);
          if (message.contains('READY') && !ready.isCompleted) ready.complete();
        },
      );
      final client = HttpClient();
      try {
        await server.start();
        await ready.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TestFailure(messages.join('\n')),
        );
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port'),
        );
        final response = await request.close();
        final keys =
            (jsonDecode(await response.transform(utf8.decoder).join()) as List)
                .cast<String>();
        expect(
          keys.any(
            (key) => key.startsWith('SUPABASE_') || key.startsWith('RESEND_'),
          ),
          false,
        );
        expect(keys, contains('PORT'));
        await server.stop();
        expect(server.isRunning, false);
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
        await rebound.close();
      } finally {
        client.close(force: true);
        await server.stop();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
