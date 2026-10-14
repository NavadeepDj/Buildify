import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class DeliveryResult {
  const DeliveryResult({
    required this.success,
    this.messageId,
    this.errorMessage,
    this.isSandbox = false,
  });

  final bool success;
  final String? messageId;
  final String? errorMessage;
  final bool isSandbox;

  factory DeliveryResult.ok({String? messageId, bool isSandbox = false}) {
    return DeliveryResult(success: true, messageId: messageId, isSandbox: isSandbox);
  }

  factory DeliveryResult.failure(String errorMessage) {
    return DeliveryResult(success: false, errorMessage: errorMessage);
  }
}

abstract class EmailDeliveryProvider {
  Future<DeliveryResult> sendVerificationEmail({
    required String recipientEmail,
    required String verificationUrl,
    required String verificationToken,
    required String userName,
    required Duration expiryDuration,
  });
}

abstract class SmsDeliveryProvider {
  Future<DeliveryResult> sendVerificationOtp({
    required String recipientPhone,
    required String otpCode,
    required Duration expiryDuration,
  });
}

/// Production email provider supporting Resend, SendGrid, custom webhooks,
/// or development sandbox when external credentials are not configured.
class ConfiguredEmailProvider implements EmailDeliveryProvider {
  ConfiguredEmailProvider({
    http.Client? httpClient,
    Map<String, String>? env,
  })  : _client = httpClient ?? http.Client(),
        _env = env ?? Platform.environment;

  final http.Client _client;
  final Map<String, String> _env;

  // In-memory capture for local sandbox inspection & testing
  static final List<Map<String, dynamic>> sandboxOutbox = [];

  String get _provider =>
      (_env['BUILDIFY_EMAIL_PROVIDER'] ?? '').trim().toLowerCase();
  String get _fromAddress =>
      _env['BUILDIFY_EMAIL_FROM'] ?? 'Buildify Auth <no-reply@buildify.me>';
  bool get _isProduction =>
      (_env['BUILDIFY_ENV'] ?? '').trim().toLowerCase() == 'production';

  @override
  Future<DeliveryResult> sendVerificationEmail({
    required String recipientEmail,
    required String verificationUrl,
    required String verificationToken,
    required String userName,
    required Duration expiryDuration,
  }) async {
    final minutes = expiryDuration.inMinutes;
    const subject = 'Verify your Buildify account';
    final textBody = '''
Hello $userName,

Thank you for registering on Buildify. Please verify your email address to activate your account.

Click the following link to verify your email (expires in $minutes minutes):
$verificationUrl

Verification Token: $verificationToken

If you did not create a Buildify account, you can safely ignore this email.
''';

    // 1. Resend API
    if (_provider == 'resend') {
      final apiKey = _env['BUILDIFY_RESEND_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        return DeliveryResult.failure(
          'Email delivery failed: BUILDIFY_RESEND_API_KEY is not configured.',
        );
      }
      try {
        final res = await _client.post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'from': _fromAddress,
            'to': [recipientEmail],
            'subject': subject,
            'text': textBody,
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>?;
          return DeliveryResult.ok(messageId: data?['id']?.toString());
        } else {
          return DeliveryResult.failure(
            'Resend provider returned error HTTP ${res.statusCode}: ${res.body}',
          );
        }
      } catch (e) {
        return DeliveryResult.failure('Failed to connect to email provider: $e');
      }
    }

    // 2. SendGrid API
    if (_provider == 'sendgrid') {
      final apiKey = _env['BUILDIFY_SENDGRID_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        return DeliveryResult.failure(
          'Email delivery failed: BUILDIFY_SENDGRID_API_KEY is not configured.',
        );
      }
      try {
        final res = await _client.post(
          Uri.parse('https://api.sendgrid.com/v3/mail/send'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'personalizations': [
              {
                'to': [{'email': recipientEmail}]
              }
            ],
            'from': {'email': _fromAddress},
            'subject': subject,
            'content': [
              {'type': 'text/plain', 'value': textBody}
            ],
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return DeliveryResult.ok(messageId: 'sg_${DateTime.now().millisecondsSinceEpoch}');
        } else {
          return DeliveryResult.failure(
            'SendGrid provider returned HTTP ${res.statusCode}: ${res.body}',
          );
        }
      } catch (e) {
        return DeliveryResult.failure('Failed to connect to SendGrid: $e');
      }
    }

    // 3. Custom Webhook
    final webhook = _env['BUILDIFY_EMAIL_WEBHOOK_URL'];
    if (webhook != null && webhook.isNotEmpty) {
      try {
        final res = await _client.post(
          Uri.parse(webhook),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': recipientEmail,
            'subject': subject,
            'verificationUrl': verificationUrl,
            'userName': userName,
            'expiresInMinutes': minutes,
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return DeliveryResult.ok(messageId: 'webhook_${DateTime.now().millisecondsSinceEpoch}');
        } else {
          return DeliveryResult.failure('Email webhook failed with HTTP ${res.statusCode}');
        }
      } catch (e) {
        return DeliveryResult.failure('Failed to connect to email webhook: $e');
      }
    }

    // 4. Memory provider explicitly configured for testing
    if (_provider == 'memory') {
      sandboxOutbox.add({
        'to': recipientEmail,
        'subject': subject,
        'verificationUrl': verificationUrl,
        'token': verificationToken,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return DeliveryResult.ok(messageId: 'mem_${sandboxOutbox.length}');
    }

    // 5. In production, unconfigured provider is a strict configuration failure
    if (_isProduction) {
      return DeliveryResult.failure(
        'Email delivery failed: No production email provider configured. Please configure BUILDIFY_EMAIL_PROVIDER.',
      );
    }

    // In local development, record to sandbox outbox and return sandbox result
    sandboxOutbox.add({
      'to': recipientEmail,
      'subject': subject,
      'verificationUrl': verificationUrl,
      'token': verificationToken,
      'timestamp': DateTime.now().toIso8601String(),
    });
    return DeliveryResult.ok(
      messageId: 'dev_sandbox_${DateTime.now().millisecondsSinceEpoch}',
      isSandbox: true,
    );
  }
}

/// Production SMS provider supporting Twilio, custom SMS webhooks,
/// or development sandbox when external credentials are not configured.
class ConfiguredSmsProvider implements SmsDeliveryProvider {
  ConfiguredSmsProvider({
    http.Client? httpClient,
    Map<String, String>? env,
  })  : _client = httpClient ?? http.Client(),
        _env = env ?? Platform.environment;

  final http.Client _client;
  final Map<String, String> _env;

  // In-memory capture for local sandbox inspection & testing
  static final List<Map<String, dynamic>> sandboxOutbox = [];

  String get _provider =>
      (_env['BUILDIFY_SMS_PROVIDER'] ?? '').trim().toLowerCase();
  bool get _isProduction =>
      (_env['BUILDIFY_ENV'] ?? '').trim().toLowerCase() == 'production';

  @override
  Future<DeliveryResult> sendVerificationOtp({
    required String recipientPhone,
    required String otpCode,
    required Duration expiryDuration,
  }) async {
    final minutes = expiryDuration.inMinutes;
    final messageBody =
        'Your Buildify verification code is $otpCode. Valid for $minutes minutes. Do not share this code.';

    // 1. Twilio SMS
    if (_provider == 'twilio') {
      final accountSid = _env['BUILDIFY_TWILIO_ACCOUNT_SID'];
      final authToken = _env['BUILDIFY_TWILIO_AUTH_TOKEN'];
      final fromNumber = _env['BUILDIFY_TWILIO_FROM_NUMBER'];

      if (accountSid == null || accountSid.isEmpty ||
          authToken == null || authToken.isEmpty ||
          fromNumber == null || fromNumber.isEmpty) {
        return DeliveryResult.failure(
          'SMS delivery failed: Missing Twilio credentials (ACCOUNT_SID, AUTH_TOKEN, FROM_NUMBER).',
        );
      }

      try {
        final basicAuth = base64Encode(utf8.encode('$accountSid:$authToken'));
        final url = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
        );
        final res = await _client.post(
          url,
          headers: {
            'Authorization': 'Basic $basicAuth',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'From': fromNumber,
            'To': recipientPhone,
            'Body': messageBody,
          },
        );

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>?;
          return DeliveryResult.ok(messageId: data?['sid']?.toString());
        } else {
          return DeliveryResult.failure(
            'Twilio provider error HTTP ${res.statusCode}: ${res.body}',
          );
        }
      } catch (e) {
        return DeliveryResult.failure('Failed to connect to Twilio SMS provider: $e');
      }
    }

    // 2. Custom SMS Webhook
    final webhook = _env['BUILDIFY_SMS_WEBHOOK_URL'];
    if (webhook != null && webhook.isNotEmpty) {
      try {
        final res = await _client.post(
          Uri.parse(webhook),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': recipientPhone,
            'body': messageBody,
            'otp': otpCode,
            'expiresInMinutes': minutes,
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return DeliveryResult.ok(messageId: 'sms_wh_${DateTime.now().millisecondsSinceEpoch}');
        } else {
          return DeliveryResult.failure('SMS webhook returned HTTP ${res.statusCode}');
        }
      } catch (e) {
        return DeliveryResult.failure('Failed to connect to SMS webhook: $e');
      }
    }

    // 3. Memory provider explicitly configured
    if (_provider == 'memory') {
      sandboxOutbox.add({
        'to': recipientPhone,
        'otp': otpCode,
        'body': messageBody,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return DeliveryResult.ok(messageId: 'mem_sms_${sandboxOutbox.length}');
    }

    // 4. In production, unconfigured provider is a strict configuration failure
    if (_isProduction) {
      return DeliveryResult.failure(
        'SMS delivery failed: No production SMS provider configured. Please configure BUILDIFY_SMS_PROVIDER.',
      );
    }

    // In local development, record to sandbox outbox and return sandbox result
    sandboxOutbox.add({
      'to': recipientPhone,
      'otp': otpCode,
      'body': messageBody,
      'timestamp': DateTime.now().toIso8601String(),
    });
    return DeliveryResult.ok(
      messageId: 'dev_sms_sandbox_${DateTime.now().millisecondsSinceEpoch}',
      isSandbox: true,
    );
  }
}
