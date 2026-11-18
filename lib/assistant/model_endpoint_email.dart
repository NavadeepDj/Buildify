import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Windows demo sender. Credentials are read at runtime on the setup host,
/// never accepted from a voice tool, compiled into an APK, or returned in errors.
class ModelEndpointEmailSender {
  ModelEndpointEmailSender({
    http.Client? client,
    Future<Map<String, String>> Function()? configuration,
  }) : _client = client ?? http.Client(),
       _loadConfiguration = configuration;
  final http.Client _client;
  final Future<Map<String, String>> Function()? _loadConfiguration;
  final Map<String, Map<String, Object?>> _sent = {};
  final Map<String, Future<Map<String, Object?>>> _pending = {};

  Future<Map<String, String>> _configuration() async {
    if (_loadConfiguration != null) return _loadConfiguration();
    final values = Map<String, String>.from(Platform.environment);
    final path = values['BUILDIFY_ENDPOINT_EMAIL_ENV_FILE'];
    if (Platform.isWindows && path != null) {
      try {
        for (final line in await File(path).readAsLines()) {
          final match = RegExp(
            r'^\s*(BUILDIFY_RESEND_API_KEY|BUILDIFY_EMAIL_FROM|BUILDIFY_ENDPOINT_EMAIL_TO)\s*=(.*)$',
          ).firstMatch(line);
          if (match == null) continue;
          var value = match[2]!.trim();
          if (value.length >= 2 &&
              ((value.startsWith('"') && value.endsWith('"')) ||
                  (value.startsWith("'") && value.endsWith("'")))) {
            value = value.substring(1, value.length - 1);
          }
          values[match[1]!] = value;
        }
      } catch (_) {
        /* Missing configuration is reported without file contents. */
      }
    }
    return values;
  }

  /// A fixed stop receipt, never arbitrary caller-supplied email content.
  Future<Map<String, Object?>> sendStopped({
    required String actionId,
    required String model,
    required String stoppedAt,
  }) async {
    final config = await _configuration();
    final key = config['BUILDIFY_RESEND_API_KEY']?.trim() ?? '';
    final recipient = config['BUILDIFY_ENDPOINT_EMAIL_TO']?.trim() ?? '';
    final sender =
        config['BUILDIFY_EMAIL_FROM']?.trim() ??
        'HostAny <notifications@hostany.app>';
    if (key.isEmpty ||
        !RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(recipient) ||
        sender.contains('\r') ||
        sender.contains('\n')) {
      return {
        'ok': false,
        'state': 'not_configured',
        'error': 'status_email_not_configured',
      };
    }
    final identity =
        sha256.convert(utf8.encode('$recipient\nstop\n$actionId')).toString();
    if (_sent[identity] case final receipt?) return receipt;
    if (_pending[identity] case final pending?) return pending;
    final pending = _deliver(
      key: key,
      sender: sender,
      recipient: recipient,
      identity: identity,
      subject: 'Your Buildify model has stopped',
      text:
          'Buildify confirmed that the model stopped.\n\n'
          'Model: $model\nStop confirmed at (UTC): $stoppedAt\n\n'
          'The model was not serving inference when this stop completed. '
          'This is a receipt for that operation, not continuous monitoring.\n',
      receipt: {'action_id': actionId, 'model': model, 'stopped_at': stoppedAt},
    );
    _pending[identity] = pending;
    try {
      final result = await pending;
      if (result['state'] == 'sent') _sent[identity] = result;
      return result;
    } finally {
      _pending.remove(identity);
    }
  }

  Future<Map<String, Object?>> send({
    required String publicEndpoint,
    required String localEndpoint,
    required String model,
    required bool authenticationRequired,
    String? resendId,
  }) async {
    final config = await _configuration();
    final key = config['BUILDIFY_RESEND_API_KEY']?.trim() ?? '';
    final recipient = config['BUILDIFY_ENDPOINT_EMAIL_TO']?.trim() ?? '';
    final sender =
        config['BUILDIFY_EMAIL_FROM']?.trim() ??
        'HostAny <notifications@hostany.app>';
    if (key.isEmpty ||
        !RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(recipient) ||
        sender.contains('\r') ||
        sender.contains('\n')) {
      return {
        'ok': false,
        'state': 'not_configured',
        'error': 'endpoint_email_not_configured',
        'summary':
            'The model endpoint is ready, but the HostAny sender needs its sending credential configured on the Windows host.',
      };
    }
    final uri = Uri.tryParse(publicEndpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return {
        'ok': false,
        'state': 'failed',
        'error': 'invalid_public_endpoint',
      };
    }
    final identity =
        sha256
            .convert(
              utf8.encode(
                '$recipient\n$publicEndpoint\n$model\n$authenticationRequired\n${resendId ?? 'initial'}',
              ),
            )
            .toString();
    if (_sent[identity] case final receipt?) return receipt;
    final existing = _pending[identity];
    if (existing != null) return existing;
    final pending = _deliver(
      key: key,
      sender: sender,
      recipient: recipient,
      identity: identity,
      subject: 'Your Buildify model endpoint',
      text:
          'Your Buildify model is running.\n\nModel: $model\n\n'
          'Open your model:\n$publicEndpoint\n\n'
          'Local model link (on the hosting computer):\n$localEndpoint\n\n'
          '${authenticationRequired ? 'Authorization: use the API key from Buildify. No credentials are included in this email.' : 'Authorization: no API key or Authorization header required.'}\n\n'
          'The public URL is temporary and works while the model, tunnel, and Windows computer stay running. '
          'The localhost URL works only on the hosting computer.\n',
      receipt: {'public_endpoint': publicEndpoint},
    );
    _pending[identity] = pending;
    try {
      final result = await pending;
      if (result['state'] == 'sent') _sent[identity] = result;
      return result;
    } finally {
      _pending.remove(identity);
    }
  }

  Future<Map<String, Object?>> _deliver({
    required String key,
    required String sender,
    required String recipient,
    required String identity,
    required String subject,
    required String text,
    required Map<String, Object?> receipt,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.resend.com/emails'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'Idempotency-Key': 'buildify-endpoint/$identity',
            },
            body: jsonEncode({
              'from': sender,
              'to': [recipient],
              'subject': subject,
              'text': text,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map && data['id'] is String) {
          return {
            'ok': true,
            'state': 'sent',
            'recipient': recipient,
            ...receipt,
            'message_id': data['id'],
            'summary': 'HostAny accepted the email for $recipient.',
          };
        }
      }
      return {
        'ok': false,
        'state': 'failed',
        'error': 'email_provider_rejected',
        'summary': 'The email provider did not accept delivery.',
      };
    } catch (_) {
      return {
        'ok': false,
        'state': 'failed',
        'error': 'email_provider_unavailable',
        'summary': 'Email delivery could not reach the provider.',
      };
    }
  }

  void close() => _client.close();
}
