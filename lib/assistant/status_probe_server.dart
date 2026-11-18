import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Opt-in authenticated hackathon tools, including paired-owner plan confirmation.
class StatusProbeServer {
  StatusProbeServer._(
    this._server,
    this._tokenHash,
    this._inspect,
    this._requestSetup,
    this._setupStatus,
    this._listTools,
    this._invokeTool,
  );

  final HttpServer _server;
  final List<int> _tokenHash;
  final Future<Map<String, Object?>> Function() _inspect;
  final Map<String, Object?> Function()? _requestSetup;
  final Map<String, Object?> Function()? _setupStatus;
  final List<Map<String, Object?>> Function()? _listTools;
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)?
  _invokeTool;
  bool _busy = false;
  Future<void>? _closing;

  int get port => _server.port;

  /// Local owner UI uses the same coordinator as authenticated voice requests.
  Future<Map<String, Object?>> invokeLocalTool(
    String name,
    Map<String, Object?> args,
  ) async {
    final invoke = _invokeTool;
    if (_closing != null || invoke == null) {
      return {'ok': false, 'error': 'voice_bridge_unavailable'};
    }
    return invoke(name, args);
  }

  static Future<StatusProbeServer> start({
    required String token,
    required Future<Map<String, Object?>> Function() inspect,
    Map<String, Object?> Function()? requestSetup,
    Map<String, Object?> Function()? setupStatus,
    List<Map<String, Object?>> Function()? listTools,
    Future<Map<String, Object?>> Function(String, Map<String, Object?>)?
    invokeTool,
    int port = 18791,
  }) async {
    if (token.length < 32 || token.length > 256 || token.trim() != token) {
      throw ArgumentError('A 32-256 character probe token is required.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final probe = StatusProbeServer._(
      server,
      sha256.convert(utf8.encode('Bearer $token')).bytes,
      inspect,
      requestSetup,
      setupStatus,
      listTools,
      invokeTool,
    );
    server.listen(probe._handle);
    return probe;
  }

  Future<void> close() => _closing ??= _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      final digest = sha256.convert(utf8.encode(authorization ?? '')).bytes;
      var difference = 0;
      for (var i = 0; i < digest.length; i++) {
        difference |= digest[i] ^ _tokenHash[i];
      }
      if (difference != 0) {
        response.statusCode = HttpStatus.unauthorized;
        response.write(jsonEncode({'ok': false, 'error': 'unauthorized'}));
        return;
      }
      if (!request.uri.hasQuery &&
          request.uri.path == '/v1/tools' &&
          request.method == 'GET' &&
          _listTools != null) {
        response.write(jsonEncode({'tools': _listTools()}));
        return;
      }
      if (!request.uri.hasQuery &&
          request.uri.path.startsWith('/v1/tools/') &&
          request.method == 'POST' &&
          _invokeTool != null) {
        final name = request.uri.path.substring('/v1/tools/'.length);
        if (!RegExp(r'^[a-z_]{1,60}$').hasMatch(name)) {
          throw const FormatException('Invalid tool');
        }
        final bytes = <int>[];
        await for (final chunk in request.timeout(const Duration(seconds: 2))) {
          bytes.addAll(chunk);
          if (bytes.length > 4096) {
            throw const FormatException('Request too large');
          }
        }
        final body =
            bytes.isEmpty
                ? <String, Object?>{}
                : jsonDecode(utf8.decode(bytes));
        if (body is! Map<String, dynamic>) {
          throw const FormatException('Object required');
        }
        final result = await _invokeTool(
          name,
          body,
        ).timeout(const Duration(seconds: 20));
        response.write(jsonEncode(result));
        return;
      }
      if (!request.uri.hasQuery &&
          request.uri.path == '/v1/setup-plan' &&
          request.method == 'POST' &&
          _requestSetup != null) {
        // A fixed, zero-argument plan request. Never accept approval or commands.
        final bytes = <int>[];
        await for (final chunk in request.timeout(const Duration(seconds: 2))) {
          bytes.addAll(chunk);
          if (bytes.length > 128) throw const FormatException('Body too large');
        }
        if (bytes.isNotEmpty) {
          final body = jsonDecode(utf8.decode(bytes));
          if (body is! Map || body.isNotEmpty) {
            throw const FormatException('No arguments supported');
          }
        }
        response.write(jsonEncode(_requestSetup()));
        return;
      }
      if (!request.uri.hasQuery &&
          request.uri.path == '/v1/setup-status' &&
          request.method == 'GET' &&
          request.contentLength <= 0 &&
          !request.headers.chunkedTransferEncoding &&
          _setupStatus != null) {
        response.write(jsonEncode(_setupStatus()));
        return;
      }
      if (request.method != 'GET' ||
          request.uri.path != '/v1/status' ||
          request.uri.hasQuery ||
          request.contentLength > 0 ||
          request.headers.chunkedTransferEncoding) {
        response.statusCode = HttpStatus.badRequest;
        response.write(
          jsonEncode({'ok': false, 'error': 'unsupported_request'}),
        );
        return;
      }
      if (_busy) {
        response.statusCode = HttpStatus.tooManyRequests;
        response.write(jsonEncode({'ok': false, 'error': 'probe_busy'}));
        return;
      }
      _busy = true;
      try {
        // Keep the lock until the underlying inspection settles, even if the
        // HTTP deadline expires. A timeout must not pile up native probes.
        final pending = Future<Map<String, Object?>>.sync(_inspect);
        unawaited(
          pending.then<void>(
            (_) => _busy = false,
            onError: (Object _, StackTrace __) {
              _busy = false;
            },
          ),
        );
        final observation = await pending.timeout(const Duration(seconds: 5));
        final server = observation['server'];
        final reading = server is Map ? server : const {};
        final value = reading['value'];
        final observedState = value is Map ? value['state'] : null;
        const allowed = {
          'stopped',
          'starting',
          'running',
          'stopping',
          'failed',
        };
        final state =
            reading['status'] == 'observed' && allowed.contains(observedState)
                ? observedState as String
                : 'unknown';
        response.write(
          jsonEncode({
            'ok': true,
            'source': 'buildify_live_app',
            'observed_at': DateTime.now().toUtc().toIso8601String(),
            'model_state': state,
            'health_verified': false,
            'summary':
                state == 'unknown'
                    ? 'Buildify is open, but model runtime state is unavailable. No inference test was performed.'
                    : 'Buildify is open. The model runtime reports $state. No inference test was performed.',
          }),
        );
      } catch (_) {
        response.statusCode = HttpStatus.serviceUnavailable;
        response.write(
          jsonEncode({'ok': false, 'error': 'inspection_unavailable'}),
        );
      }
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'ok': false, 'error': 'invalid_request'}));
    } finally {
      await response.close();
    }
  }
}
