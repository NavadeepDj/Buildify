import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'native_server_bridge.dart';
import 'process_server.dart';

typedef DesktopProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

/// Pure-Dart backend for desktop (Windows/Linux/macOS).
///
/// Desktop platforms have no MethodChannel implementation of `buildify.ai/server`,
/// but unlike iOS they *can* spawn processes — so we run the bundled
/// `llama-server` and `cloudflared` binaries directly via [Process.start].
///
/// Binary resolution order for each tool:
///   1. Env override — `BUILDIFY_LLAMA_SERVER` / `BUILDIFY_CLOUDFLARED`
///   2. `<dir of app executable>/native/<os>/<name>` and `<dir>/<name>`
///   3. bare name on PATH (runInShell)
class DesktopServerBridge implements ServerBridge {
  DesktopServerBridge({
    DesktopProcessStarter? startProcess,
    Future<String> Function(String, String)? resolveBinary,
    Future<bool> Function(int)? healthProbe,
  }) : _startProcess = startProcess ?? _spawn,
       _binary = resolveBinary,
       _health = healthProbe ?? _probe;

  final DesktopProcessStarter _startProcess;
  final Future<String> Function(String, String)? _binary;
  final Future<bool> Function(int) _health;
  String _serverStatus = 'stopped';
  Future<NativeServerResponse>? _serverStarting;
  Future<NativeTunnelResponse>? _tunnelStarting;

  static Future<Process> _spawn(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) => Process.start(
    executable,
    arguments,
    runInShell: false,
    environment: environment,
    includeParentEnvironment: false,
  );

  static Future<bool> _probe(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static void _lines(Stream<List<int>> stream, void Function(String) consume) {
    stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(consume, onError: (_) {});
  }

  static String _safe(String value, String? secret) {
    final text =
        secret == null || secret.isEmpty
            ? value
            : value.replaceAll(secret, '[redacted]');
    return text.length > 500 ? text.substring(0, 500) : text;
  }

  static Future<void> _terminate(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 3));
    }
  }

  Process? _serverProc;
  int _serverPort = 8080;
  String? _serverError;

  Process? _tunnelProc;
  String? _tunnelUrl;
  bool _isGateway = false;
  String? _tunnelError;
  String _tunnelStatus = 'stopped';

  static final _osDir =
      Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux');
  static String get _exeExt => Platform.isWindows ? '.exe' : '';

  Future<String> _resolveBinary(String name, String envVar) async {
    if (_binary != null) return _binary(name, envVar);
    final override = Platform.environment[envVar];
    if (override != null && override.isNotEmpty) {
      if (!p.isAbsolute(override) || !File(override).existsSync()) {
        throw FileSystemException(
          '$envVar must name an existing absolute executable.',
        );
      }
      return override;
    }
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, 'native', _osDir, '$name$_exeExt'),
      p.join(exeDir, '$name$_exeExt'),
      ...?Platform.environment['PATH']
          ?.split(Platform.isWindows ? ';' : ':')
          .where((entry) => entry.isNotEmpty && p.isAbsolute(entry))
          .map((entry) => p.join(entry, '$name$_exeExt')),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    throw FileSystemException(
      '$name$_exeExt is missing. Use the complete app bundle or set $envVar to its absolute path.',
    );
  }

  @override
  Future<String?> getModelBasePath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final models = Directory(p.join(dir.path, 'models'));
      if (!models.existsSync()) models.createSync(recursive: true);
      return models.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<String?> getTailscaleIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // Tailscale assigns addresses in the 100.64.0.0/10 CGNAT range.
          final bytes = addr.rawAddress;
          if (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getDeviceMetrics() async {
    if (Platform.isWindows) {
      try {
        final support = await getApplicationSupportDirectory();
        return await const MethodChannel(
          'hostany/windows',
        ).invokeMapMethod<String, dynamic>('getDeviceMetrics', {
          'storage_path': support.path,
        });
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    }
    return null;
  }

  @override
  Future<NativeServerResponse> startServer({
    required String modelPath,
    required int port,
    String? apiKey,
    int idleMinutes = 0,
    int batteryStopPercent = 0,
    bool thermalStop = true,
  }) =>
      _serverStarting ??= _startServer(
        modelPath,
        port,
        apiKey,
      ).whenComplete(() => _serverStarting = null);

  Future<NativeServerResponse> _startServer(
    String modelPath,
    int port,
    String? apiKey,
  ) async {
    if (_serverProc != null) {
      return NativeServerResponse(
        ok: true,
        status: _serverStatus,
        port: _serverPort,
      );
    }
    _serverError = null;
    _serverPort = port;

    if (port < 1 || port > 65535 || !File(modelPath).existsSync()) {
      _serverError = 'model file not found: $modelPath';
      return NativeServerResponse(
        ok: false,
        status: 'stopped',
        message: _serverError,
      );
    }

    try {
      final bin = await _resolveBinary('llama-server', 'BUILDIFY_LLAMA_SERVER');
      // Do not mistake another service's /health for this model's readiness.
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      await socket.close();
      final args = <String>[
        '--model',
        modelPath,
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        if (apiKey != null && apiKey.isNotEmpty) ...['--api-key', apiKey],
      ];
      final process = await _startProcess(
        bin,
        args,
        ProcessServer.buildChildEnvironment(port, const {}),
      );
      _serverProc = process;
      _serverStatus = 'starting';
      _lines(process.stdout, (_) {});
      _lines(process.stderr, (line) {
        if (identical(_serverProc, process) &&
            line.toLowerCase().contains('error')) {
          _serverError = _safe(line.trim(), apiKey);
        }
      });
      unawaited(
        process.exitCode.then((code) {
          if (!identical(_serverProc, process)) return;
          _serverProc = null;
          _serverStatus = 'stopped';
          if (code != 0) {
            _serverError ??= 'llama-server exited with code $code.';
          }
        }),
      );
      return NativeServerResponse(ok: true, status: 'starting', port: port);
    } catch (e) {
      _serverError = _safe('failed to launch llama-server: $e', apiKey);
      _serverStatus = 'stopped';
      _serverProc = null;
      return NativeServerResponse(
        ok: false,
        status: 'stopped',
        message: _serverError,
      );
    }
  }

  @override
  Future<NativeServerResponse> stopServer() async {
    await _serverStarting;
    final proc = _serverProc;
    if (proc == null) {
      return const NativeServerResponse(ok: true, status: 'stopped');
    }
    try {
      await _terminate(proc);
    } catch (_) {
      return const NativeServerResponse(
        ok: false,
        status: 'stopping',
        message: 'The model process did not stop. Retry stopping.',
      );
    }
    if (identical(_serverProc, proc)) _serverProc = null;
    _serverStatus = 'stopped';
    return const NativeServerResponse(ok: true, status: 'stopped');
  }

  @override
  Future<NativeServerStatus?> getServerStatus() async {
    final process = _serverProc;
    if (process != null &&
        _serverStatus == 'starting' &&
        await _health(_serverPort)) {
      if (identical(_serverProc, process)) _serverStatus = 'running';
    }
    return NativeServerStatus(
      status: _serverStatus,
      port: _serverPort,
      lastError: _serverError,
    );
  }

  @override
  Future<NativeTunnelResponse> startTunnel({
    required int port,
    String? tunnelUrl,
    String? tunnelToken,
  }) =>
      _tunnelStarting ??= _startTunnel(
        port,
        tunnelToken,
      ).whenComplete(() => _tunnelStarting = null);

  Future<NativeTunnelResponse> _startTunnel(
    int port,
    String? tunnelToken,
  ) async {
    if (_tunnelProc != null) {
      return NativeTunnelResponse(
        ok: _isGateway == (tunnelToken != null),
        status: _tunnelStatus,
        message: 'Stop the active tunnel before switching tunnel modes.',
      );
    }
    _tunnelUrl = null;
    _tunnelError = null;
    _isGateway = tunnelToken != null;
    _tunnelStatus = 'starting';
    if (port < 1 || port > 65535) {
      return const NativeTunnelResponse(
        ok: false,
        status: 'failed',
        message: 'Invalid tunnel port.',
      );
    }
    try {
      final bin = await _resolveBinary('cloudflared', 'BUILDIFY_CLOUDFLARED');
      final process = await _startProcess(
        bin,
        tunnelToken == null
            ? ['tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:$port']
            : ['tunnel', '--no-autoupdate', 'run'],
        ProcessServer.buildChildEnvironment(port, {
          if (tunnelToken != null) 'TUNNEL_TOKEN': tunnelToken,
        }),
      );
      _tunnelProc = process;
      // The assigned URL alone does not prove a connected tunnel.
      var connected = false;
      void scan(String line) {
        if (!identical(_tunnelProc, process)) return;
        if (line.contains('Registered tunnel connection')) {
          connected = true;
          _tunnelError = null;
        }
        final match = RegExp(
          r'https://[a-z0-9-]+\.trycloudflare\.com',
        ).firstMatch(line);
        if (match != null) {
          _tunnelUrl = match.group(0);
        }
        if (connected && (tunnelToken != null || _tunnelUrl != null)) {
          _tunnelStatus = 'running';
        }
        if (line.contains(' ERR ') || line.toLowerCase().contains('error')) {
          _tunnelError = _safe(line, tunnelToken);
        }
      }

      _lines(process.stdout, scan);
      _lines(process.stderr, scan);
      unawaited(
        process.exitCode.then((code) {
          if (!identical(_tunnelProc, process)) return;
          _tunnelProc = null;
          if (_tunnelStatus != 'stopped') _tunnelStatus = 'failed';
          _tunnelError ??= 'cloudflared exited with code $code.';
        }),
      );
      return NativeTunnelResponse(ok: true, status: 'starting');
    } catch (e) {
      _tunnelError = _safe('failed to launch cloudflared: $e', tunnelToken);
      _tunnelStatus = 'failed';
      _tunnelProc = null;
      return NativeTunnelResponse(
        ok: false,
        status: 'failed',
        message: _tunnelError,
      );
    }
  }

  @override
  Future<NativeTunnelResponse> stopTunnel() async {
    await _tunnelStarting;
    final proc = _tunnelProc;
    if (proc != null) {
      try {
        await _terminate(proc);
      } catch (_) {
        return const NativeTunnelResponse(
          ok: false,
          status: 'failed',
          message: 'The tunnel process did not stop. Retry stopping.',
        );
      }
    }
    if (identical(_tunnelProc, proc)) _tunnelProc = null;
    _tunnelStatus = 'stopped';
    _tunnelUrl = null;
    _tunnelError = null;
    return const NativeTunnelResponse(ok: true, status: 'stopped');
  }

  @override
  Future<NativeTunnelStatus?> getTunnelStatus() async {
    return NativeTunnelStatus(
      status: _tunnelStatus,
      publicUrl: _tunnelUrl,
      isGateway: _isGateway,
      lastError: _tunnelError,
    );
  }
}
