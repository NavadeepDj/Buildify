import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model_operations.dart';

/// Small, bounded inference probe against the local runtime only. Never follows
/// a redirect carrying the inference credential to another host.
class ModelEndpointVerifier {
  ModelEndpointVerifier({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.readinessTimeout = const Duration(seconds: 45),
    this.readinessRetryInterval = const Duration(milliseconds: 500),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final Duration readinessTimeout;
  final Duration readinessRetryInterval;
  final _closed = Completer<void>();
  Future<Duration> verify({required int port, String? apiKey}) async {
    try {
      _ensureOpen();
      return await Future.any<Duration>([
        _verify(port: port, apiKey: apiKey),
        _closed.future.then<Duration>(
          (_) => throw const ModelOperationFailure('inference_failed'),
        ),
      ]).timeout(readinessTimeout + timeout);
    } catch (_) {
      close();
      throw const ModelOperationFailure('inference_failed');
    }
  }

  void _ensureOpen() {
    if (_closed.isCompleted) {
      throw const ModelOperationFailure('inference_failed');
    }
  }

  Future<void> _waitUntilReady(int port, String? apiKey) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < readinessTimeout) {
      _ensureOpen();
      final remaining = readinessTimeout - watch.elapsed;
      final attemptTimeout =
          remaining < const Duration(seconds: 3)
              ? remaining
              : const Duration(seconds: 3);
      try {
        final request = http.Request(
          'GET',
          Uri.parse('http://127.0.0.1:$port/health'),
        )..followRedirects = false;
        if (apiKey != null && apiKey.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $apiKey';
        }
        final status = await (() async {
          final response = await _client.send(request);
          await response.stream.drain<void>();
          return response.statusCode;
        })().timeout(attemptTimeout);
        _ensureOpen();
        if (status == 200) return;
        // llama.cpp returns 503 while loading. Other HTTP failures (including
        // redirects/authentication) cannot be repaired by repeating requests.
        if (status != 503) {
          throw const ModelOperationFailure('inference_failed');
        }
      } on http.ClientException {
        // The native process may exist before its listener has bound the port.
      } on TimeoutException {
        // A loading runtime can briefly be unable to answer its health route.
      }
      final delayBudget = readinessTimeout - watch.elapsed;
      if (delayBudget <= Duration.zero) break;
      await Future.any<void>([
        Future<void>.delayed(
          readinessRetryInterval < delayBudget
              ? readinessRetryInterval
              : delayBudget,
        ),
        _closed.future,
      ]);
    }
    throw const ModelOperationFailure('inference_failed');
  }

  Future<Duration> _verify({required int port, String? apiKey}) async {
    if (port < 1 || port > 65535) {
      throw const ModelOperationFailure('inference_failed');
    }
    await _waitUntilReady(port, apiKey);
    _ensureOpen();
    final watch = Stopwatch()..start();
    try {
      final request =
          http.Request(
              'POST',
              Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
            )
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'messages': [
                {'role': 'user', 'content': 'Reply with one short greeting.'},
              ],
              'max_tokens': 16,
              'temperature': 0,
              'stream': false,
            });
      if (apiKey != null && apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw const ModelOperationFailure('inference_failed');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > 65536) {
          throw const ModelOperationFailure('inference_failed');
        }
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map ||
          body['choices'] is! List ||
          (body['choices'] as List).isEmpty) {
        throw const ModelOperationFailure('inference_failed');
      }
      final first = (body['choices'] as List).first;
      final content =
          first is Map && first['message'] is Map
              ? first['message']['content']
              : null;
      if (content is! String || content.trim().isEmpty) {
        throw const ModelOperationFailure('inference_failed');
      }
      return watch.elapsed;
    } catch (_) {
      throw const ModelOperationFailure('inference_failed');
    }
  }

  void close() {
    if (_closed.isCompleted) return;
    _closed.complete();
    if (_ownsClient) _client.close();
  }
}
