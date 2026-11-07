import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'management_api_config.dart';

class ManagementAccount {
  const ManagementAccount({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

enum ManagementFailureKind {
  signInRequired,
  confirmationRequired,
  accessDenied,
  rateLimited,
  unavailable,
  invalidResponse,
}

class ManagementFailure implements Exception {
  const ManagementFailure(this.kind, {this.retryAfterSeconds});
  final ManagementFailureKind kind;
  final int? retryAfterSeconds;

  String get message => switch (kind) {
    ManagementFailureKind.signInRequired =>
      'Sign in again to load your cloud profile.',
    ManagementFailureKind.confirmationRequired =>
      'Confirm your email before loading your cloud profile.',
    ManagementFailureKind.accessDenied =>
      'Your account cannot access this cloud profile.',
    ManagementFailureKind.rateLimited =>
      'Too many requests. Please wait before trying again.',
    ManagementFailureKind.unavailable =>
      'Could not reach your cloud profile. Check your connection and try again.',
    ManagementFailureKind.invalidResponse =>
      'Your cloud profile could not be loaded. Please try again later.',
  };

  @override
  String toString() => message;
}

/// Request-scoped credentials, never persisted or included in diagnostics.
class ManagementSession {
  const ManagementSession({required this.userId, required this.accessToken});
  final String userId;
  final String accessToken;
  @override
  String toString() => 'ManagementSession(credentials redacted)';
}

abstract interface class ManagementSessionSource {
  Future<ManagementSession?> read({bool refresh = false});
  bool isCurrentUser(String id);
}

class SupabaseManagementSessionSource implements ManagementSessionSource {
  SupabaseManagementSessionSource(this.client);
  final sb.SupabaseClient client;

  @override
  Future<ManagementSession?> read({bool refresh = false}) async {
    var session = client.auth.currentSession;
    if (session == null) return null;
    try {
      if (refresh || session.isExpired) {
        session =
            (await client.auth.refreshSession().timeout(
              const Duration(seconds: 12),
            )).session;
      }
    } on sb.AuthException {
      throw const ManagementFailure(ManagementFailureKind.signInRequired);
    } catch (_) {
      throw const ManagementFailure(ManagementFailureKind.unavailable);
    }
    if (session == null ||
        session.isExpired ||
        session.user.emailConfirmedAt == null) {
      return null;
    }
    return ManagementSession(
      userId: session.user.id,
      accessToken: session.accessToken,
    );
  }

  @override
  bool isCurrentUser(String id) => client.auth.currentSession?.user.id == id;
}

class ManagementAccountService {
  ManagementAccountService({
    required this.config,
    required this.sessions,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 12),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final ManagementApiConfig config;
  final ManagementSessionSource sessions;
  final http.Client Function() _clientFactory;
  final Duration timeout;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<ManagementAccount> fetchAccount() async {
    String? expectedUserId;
    for (var attempt = 0; attempt < 2; attempt++) {
      final session = await sessions.read(refresh: attempt == 1);
      if (session == null ||
          session.accessToken.isEmpty ||
          session.accessToken.contains(RegExp(r'\s'))) {
        throw const ManagementFailure(ManagementFailureKind.signInRequired);
      }
      if (expectedUserId != null && session.userId != expectedUserId) {
        throw const ManagementFailure(ManagementFailureKind.signInRequired);
      }
      expectedUserId ??= session.userId;
      final client = _clientFactory();
      try {
        final response = await _exchange(client, session).timeout(timeout);
        if (!sessions.isCurrentUser(session.userId)) {
          throw const ManagementFailure(ManagementFailureKind.signInRequired);
        }
        if (response.status == 401 && attempt == 0) continue;
        if (response.status == 401) {
          throw const ManagementFailure(ManagementFailureKind.signInRequired);
        }
        if (response.status == 403) {
          final confirmation =
              response.body?['error'] is Map &&
              (response.body!['error'] as Map)['code'] ==
                  'email_confirmation_required';
          throw ManagementFailure(
            confirmation
                ? ManagementFailureKind.confirmationRequired
                : ManagementFailureKind.accessDenied,
          );
        }
        if (response.status == 429) {
          final retry = response.headers['retry-after'] ?? '';
          throw ManagementFailure(
            ManagementFailureKind.rateLimited,
            retryAfterSeconds:
                RegExp(r'^[1-9][0-9]{0,5}$').hasMatch(retry)
                    ? int.parse(retry)
                    : 60,
          );
        }
        if (response.status != 200) {
          throw const ManagementFailure(ManagementFailureKind.unavailable);
        }
        final body = response.body;
        final data = body?['data'];
        final requestId = body?['request_id'];
        if (body == null ||
            body.keys.toSet().difference({'data', 'request_id'}).isNotEmpty ||
            data is! Map ||
            data.length != 2 ||
            data['id'] != session.userId ||
            data['id'] is! String ||
            !_uuid.hasMatch(data['id'] as String) ||
            data['display_name'] is! String ||
            (data['display_name'] as String).trim().isEmpty ||
            (data['display_name'] as String).runes.length > 80 ||
            requestId is! String ||
            !_uuid.hasMatch(requestId) ||
            response.headers['x-request-id'] != requestId) {
          throw const ManagementFailure(ManagementFailureKind.invalidResponse);
        }
        return ManagementAccount(
          id: data['id'] as String,
          displayName: data['display_name'] as String,
        );
      } on ManagementFailure {
        rethrow;
      } catch (_) {
        throw const ManagementFailure(ManagementFailureKind.unavailable);
      } finally {
        client.close();
      }
    }
    throw const ManagementFailure(ManagementFailureKind.signInRequired);
  }

  Future<_Reply> _exchange(
    http.Client client,
    ManagementSession session,
  ) async {
    final request =
        http.Request('GET', Uri.parse('${config.baseUri}/v1/account'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer ${session.accessToken}',
            'apikey': config.publicKey,
            'Accept': 'application/json',
          });
    final reply = await client.send(request);
    final bytes = <int>[];
    await for (final chunk in reply.stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const ManagementFailure(ManagementFailureKind.invalidResponse);
      }
      bytes.addAll(chunk);
    }
    Map<String, dynamic>? body;
    if (reply.headers['content-type']?.toLowerCase().startsWith(
          'application/json',
        ) ??
        false) {
      try {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map<String, dynamic>) body = value;
      } catch (_) {
        /* Gateway/transport errors may not use the application schema. */
      }
    }
    return _Reply(reply.statusCode, reply.headers, body);
  }
}

class _Reply {
  const _Reply(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;
}
