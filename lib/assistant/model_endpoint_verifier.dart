import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model_operations.dart';

/// Small, bounded inference probe against the local runtime only. Never follows
/// a redirect carrying the inference credential to another host.
class ModelEndpointVerifier {
  ModelEndpointVerifier({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  Future<Duration> verify({required int port, String? apiKey}) async {
    try {
      return await _verify(port: port, apiKey: apiKey).timeout(timeout);
    } catch (_) {
      if (_ownsClient) _client.close();
      throw const ModelOperationFailure('inference_failed');
    }
  }

  Future<Duration> _verify({required int port, String? apiKey}) async {
    if (port < 1 || port > 65535) {
      throw const ModelOperationFailure('inference_failed');
    }
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
    if (_ownsClient) _client.close();
  }
}
