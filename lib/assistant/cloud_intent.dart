import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/hosted_account_provider.dart';
import '../providers/management_account_provider.dart';
import '../services/management_account_service.dart';
import '../services/management_api_config.dart';
import 'model_recommendation.dart';

final cloudIntentServiceProvider = Provider<CloudIntentService?>((ref) {
  final config = ref.watch(managementApiConfigProvider);
  final client = ref.watch(hostedClientProvider);
  if (config == null || client == null) return null;
  return CloudIntentService(config, SupabaseManagementSessionSource(client));
});

class IntentMessage {
  const IntentMessage(this.role, this.text);
  final String role, text;
  Map<String, String> toJson() => {'role': role, 'text': text};
}

class CloudIntent {
  const CloudIntent(
    this.status,
    this.task,
    this.preference,
    this.scope,
    this.reply,
  );
  final String status, task, scope, reply;
  final ModelPreference preference;
  bool get canPrepare => status == 'ready' && scope == 'device_network';

  factory CloudIntent.parse(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        !['ready', 'clarify', 'unsupported'].contains(value['status']) ||
        ![
          'short_answers',
          'multilingual',
          'reasoning',
        ].contains(value['task']) ||
        !['speed', 'balanced', 'quality'].contains(value['preference']) ||
        !['device_network', 'public', 'unspecified'].contains(value['scope']) ||
        value['reply'] is! String ||
        (value['reply'] as String).trim().isEmpty ||
        (value['reply'] as String).length > 600 ||
        (value['status'] == 'ready' && value['scope'] != 'device_network')) {
      throw const IntentFailure(
        'The assistant returned an invalid plan. Try again.',
      );
    }
    return CloudIntent(
      value['status'],
      value['task'],
      ModelPreference.values.byName(value['preference']),
      value['scope'],
      value['reply'],
    );
  }
}

class IntentFailure implements Exception {
  const IntentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sends only the displayed conversation, never device paths, files or settings.
class CloudIntentService {
  CloudIntentService(
    this.config,
    this.sessions, {
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;
  final ManagementApiConfig config;
  final ManagementSessionSource sessions;
  final http.Client Function() clientFactory;

  Future<CloudIntent> interpret(List<IntentMessage> messages) async {
    final body = jsonEncode({
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    if (messages.isEmpty ||
        messages.length > 8 ||
        utf8.encode(body).length > 8192 ||
        messages.last.role != 'user' ||
        messages.asMap().entries.any(
          (e) =>
              e.value.role != (e.key.isEven ? 'user' : 'assistant') ||
              e.value.text.trim().isEmpty ||
              e.value.text.length > 1500,
        )) {
      throw const IntentFailure(
        'Start a new conversation or shorten your request.',
      );
    }
    try {
      return await _interpret(body);
    } on IntentFailure {
      rethrow;
    } catch (_) {
      throw const IntentFailure(
        'Cloud assistant unavailable. Retry or use the setup controls below.',
      );
    }
  }

  Future<CloudIntent> _interpret(String body) async {
    String? userId;
    for (var attempt = 0; attempt < 2; attempt++) {
      final session = await sessions
          .read(refresh: attempt == 1)
          .timeout(const Duration(seconds: 12));
      if (session == null ||
          session.accessToken.isEmpty ||
          session.accessToken.contains(RegExp(r'\s')) ||
          (userId != null && userId != session.userId) ||
          !sessions.isCurrentUser(session.userId)) {
        throw const IntentFailure(
          'Sign in with a confirmed account to use the cloud assistant.',
        );
      }
      userId = session.userId;
      final client = clientFactory();
      try {
        final result = await (() async {
          final request =
              http.Request(
                  'POST',
                  Uri.parse('${config.baseUri}/v1/assistant/intent'),
                )
                ..followRedirects = false
                ..headers.addAll({
                  'Authorization': 'Bearer ${session.accessToken}',
                  'apikey': config.publicKey,
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                })
                ..body = body;
          final response = await client.send(request);
          final bytes = <int>[];
          await for (final chunk in response.stream) {
            if (bytes.length + chunk.length > 16384) {
              throw const IntentFailure('Invalid assistant response.');
            }
            bytes.addAll(chunk);
          }
          return (response, bytes);
        })().timeout(const Duration(seconds: 15));
        if (!sessions.isCurrentUser(session.userId)) {
          throw const IntentFailure(
            'Your account changed. Start a new conversation.',
          );
        }
        final (response, bytes) = result;
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const IntentFailure(
            'Sign in with a confirmed account to use the cloud assistant.',
          );
        }
        if (response.statusCode == 429) {
          throw const IntentFailure(
            'Too many assistant requests. Wait a minute and retry.',
          );
        }
        if (response.statusCode != 200) {
          throw const IntentFailure(
            'Cloud assistant is not available. Use the setup controls below.',
          );
        }
        if (!(response.headers['content-type'] ?? '').startsWith(
          'application/json',
        )) {
          throw const IntentFailure('Invalid assistant response.');
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic> ||
            decoded.length != 2 ||
            decoded['request_id'] is! String ||
            response.headers['x-request-id'] != decoded['request_id']) {
          throw const IntentFailure('Invalid assistant response.');
        }
        return CloudIntent.parse(decoded['data']);
      } finally {
        client.close();
      }
    }
    throw const IntentFailure('Sign in again to use the cloud assistant.');
  }
}
