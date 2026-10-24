import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class AuthSecurityUtils {
  static final Random _secureRandom = Random.secure();

  /// Normalizes and validates an email address.
  /// Returns normalized email (lowercased, trimmed) or null if invalid.
  static String? normalizeEmail(String? rawEmail) {
    if (rawEmail == null) return null;
    final trimmed = rawEmail.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    // Standard RFC-5322 compliant regex for practical email validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&'
      "'"
      r'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
    );
    if (!emailRegex.hasMatch(trimmed)) return null;
    return trimmed;
  }

  /// Normalizes and validates a phone number to standard E.164 format.
  /// Handles input with or without country code.
  static String? normalizePhone(String? rawPhone, {String defaultCountryCode = '+1'}) {
    if (rawPhone == null) return null;
    var cleaned = rawPhone.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.isEmpty) return null;

    if (!cleaned.startsWith('+')) {
      final code = defaultCountryCode.startsWith('+')
          ? defaultCountryCode
          : '+$defaultCountryCode';
      cleaned = '$code$cleaned';
    }

    // E.164 allows 10 to 15 digits following '+'
    final e164Regex = RegExp(r'^\+[1-9]\d{7,14}$');
    if (!e164Regex.hasMatch(cleaned)) return null;
    return cleaned;
  }

  /// Generates a cryptographically random salt string.
  static String generateSalt({int length = 16}) {
    final bytes = List<int>.generate(length, (_) => _secureRandom.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generates a cryptographically random, single-use URL-safe token.
  static String generateSecureToken({int byteLength = 32}) {
    final bytes = List<int>.generate(byteLength, (_) => _secureRandom.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generates a cryptographically random 6-digit numeric OTP.
  static String generateSecureOtp({int length = 6}) {
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_secureRandom.nextInt(10));
    }
    return buffer.toString();
  }

  /// Hashes a secret (token or OTP) with salt using SHA-256.
  static String hashSecret(String secret, String salt) {
    final key = utf8.encode(salt);
    final bytes = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  /// Constant-time string equality check to prevent timing attacks.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Securely hashes a user password with per-user salt.
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password:$salt');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Masks an email for safe client-side display (e.g. j***e@example.com).
  static String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return '***';
    final user = parts[0];
    final domain = parts[1];
    if (user.length <= 2) {
      return '${user[0]}***@$domain';
    }
    return '${user[0]}***${user[user.length - 1]}@$domain';
  }

  /// Masks a phone number for safe client-side display (e.g. +1415***2671).
  static String maskPhone(String phone) {
    if (phone.length <= 6) return '***';
    final start = phone.substring(0, phone.length - 4);
    final end = phone.substring(phone.length - 4);
    final maskedPrefix = start.length > 4
        ? '${start.substring(0, 3)}***'
        : '***';
    return '$maskedPrefix$end';
  }
}
