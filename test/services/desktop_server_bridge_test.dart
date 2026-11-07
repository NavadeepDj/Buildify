import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:buildify_flutter/services/desktop_server_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _Process implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exited = Completer<int>();
  int kills = 0;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exited.future;
  void finish(int code) {
    if (!exited.isCompleted) exited.complete(code);
    unawaited(out.close());
    unawaited(err.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    finish(0);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<int> _port() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late Directory directory;
  late File model;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hostany bridge ');
    model = await File(
      '${directory.path}/model & special.gguf',
    ).writeAsString('synthetic');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'model stays starting until healthy and arguments remain separate',
    () async {
      var healthy = false;
      final process = _Process();
      final bridge = DesktopServerBridge(
        resolveBinary: (_, _) async => 'C:/tools with spaces/llama-server.exe',
        healthProbe: (_) async => healthy,
        startProcess: (exe, args, env) async {
          expect(exe, 'C:/tools with spaces/llama-server.exe');
          expect(args[args.indexOf('--model') + 1], model.path);
          expect(
            env.keys.any(
              (key) => key.startsWith('SUPABASE_') || key.startsWith('RESEND_'),
            ),
            false,
          );
          return process;
        },
      );
      expect(
        (await bridge.startServer(
          modelPath: model.path,
          port: await _port(),
        )).ok,
        true,
      );
      expect((await bridge.getServerStatus())?.status, 'starting');
      healthy = true;
      expect((await bridge.getServerStatus())?.status, 'running');
      expect((await bridge.stopServer()).ok, true);
      expect(process.kills, 1);
      expect((await bridge.getServerStatus())?.status, 'stopped');
    },
  );

  test(
    'concurrent starts launch once; stop during startup waits and terminates',
    () async {
      final pending = Completer<Process>();
      final process = _Process();
      var starts = 0;
      final bridge = DesktopServerBridge(
        resolveBinary: (_, _) async => 'synthetic',
        startProcess: (_, _, _) {
          starts++;
          return pending.future;
        },
      );
      final port = await _port();
      final first = bridge.startServer(modelPath: model.path, port: port);
      final second = bridge.startServer(modelPath: model.path, port: port);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final stopping = bridge.stopServer();
      pending.complete(process);
      await Future.wait([first, second, stopping]);
      expect(starts, 1);
      expect(process.kills, 1);
    },
  );

  test(
    'occupied port is rejected without launching or probing another app',
    () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var launches = 0;
      final bridge = DesktopServerBridge(
        resolveBinary: (_, _) async => 'synthetic',
        startProcess: (_, _, _) async {
          launches++;
          return _Process();
        },
      );
      try {
        expect(
          (await bridge.startServer(
            modelPath: model.path,
            port: socket.port,
          )).ok,
          false,
        );
        expect(launches, 0);
      } finally {
        await socket.close();
      }
    },
  );

  test('crashed model becomes stopped and logs redact the API key', () async {
    final process = _Process();
    final bridge = DesktopServerBridge(
      resolveBinary: (_, _) async => 'synthetic',
      startProcess: (_, _, _) async => process,
    );
    await bridge.startServer(
      modelPath: model.path,
      port: await _port(),
      apiKey: 'synthetic-private-key',
    );
    process.err.add(utf8.encode('error synthetic-private-key\n'));
    await Future<void>.delayed(Duration.zero);
    process.finish(7);
    await Future<void>.delayed(Duration.zero);
    final status = await bridge.getServerStatus();
    expect(status?.status, 'stopped');
    expect(status?.lastError, contains('[redacted]'));
    expect(status?.lastError, isNot(contains('synthetic-private-key')));
  });

  test(
    'tunnel assembles split URL lines and waits for an actual connection',
    () async {
      final process = _Process();
      final bridge = DesktopServerBridge(
        resolveBinary: (_, _) async => 'synthetic',
        startProcess: (_, _, _) async => process,
      );
      await bridge.startTunnel(port: 8123);
      process.err.add(utf8.encode('https://test-host.trycloud'));
      process.err.add(utf8.encode('flare.com\n'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await bridge.getTunnelStatus())?.publicUrl,
        'https://test-host.trycloudflare.com',
      );
      expect((await bridge.getTunnelStatus())?.status, 'starting');
      process.err.add(utf8.encode('Registered tunnel connection\n'));
      await Future<void>.delayed(Duration.zero);
      expect((await bridge.getTunnelStatus())?.status, 'running');
      await bridge.stopTunnel();
      expect(process.kills, 1);
      expect((await bridge.getTunnelStatus())?.publicUrl, null);
    },
  );

  test(
    'named tunnel token stays in child environment and is redacted on failure',
    () async {
      final process = _Process();
      final bridge = DesktopServerBridge(
        resolveBinary: (_, _) async => 'synthetic',
        startProcess: (_, args, env) async {
          expect(args.join(' '), isNot(contains('synthetic-token')));
          expect(env['TUNNEL_TOKEN'], 'synthetic-token');
          return process;
        },
      );
      await bridge.startTunnel(port: 8123, tunnelToken: 'synthetic-token');
      process.err.add(utf8.encode(' ERR bad synthetic-token\n'));
      await Future<void>.delayed(Duration.zero);
      process.finish(1);
      await Future<void>.delayed(Duration.zero);
      final status = await bridge.getTunnelStatus();
      expect(status?.status, 'failed');
      expect(status?.lastError, contains('[redacted]'));
    },
  );
}
