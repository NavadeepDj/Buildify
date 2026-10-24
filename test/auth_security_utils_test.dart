import 'package:flutter_test/flutter_test.dart';
import 'package:buildify_flutter/services/auth_security_utils.dart';

void main() {
  group('AuthSecurityUtils Tests', () {
    test('normalizeEmail normalizes valid emails and trims whitespace', () {
      expect(
        AuthSecurityUtils.normalizeEmail('  User.Name@Example.COM  '),
        equals('user.name@example.com'),
      );
      expect(
        AuthSecurityUtils.normalizeEmail('dev+test@buildify.me'),
        equals('dev+test@buildify.me'),
      );
    });

    test('normalizeEmail rejects invalid email patterns', () {
      expect(AuthSecurityUtils.normalizeEmail(''), isNull);
      expect(AuthSecurityUtils.normalizeEmail('   '), isNull);
      expect(AuthSecurityUtils.normalizeEmail('plainaddress'), isNull);
      expect(AuthSecurityUtils.normalizeEmail('@missingusername.com'), isNull);
      expect(AuthSecurityUtils.normalizeEmail('missingdomain@.com'), isNull);
    });

    test('normalizePhone formats and normalizes phone numbers to E.164', () {
      expect(
        AuthSecurityUtils.normalizePhone('+1 (415) 555-2671'),
        equals('+14155552671'),
      );
      expect(
        AuthSecurityUtils.normalizePhone('4155552671', defaultCountryCode: '+1'),
        equals('+14155552671'),
      );
      expect(
        AuthSecurityUtils.normalizePhone('+91 98765 43210'),
        equals('+919876543210'),
      );
      expect(
        AuthSecurityUtils.normalizePhone('+44 20 7946 0958'),
        equals('+442079460958'),
      );
    });

    test('normalizePhone rejects invalid phones', () {
      expect(AuthSecurityUtils.normalizePhone(''), isNull);
      expect(AuthSecurityUtils.normalizePhone('123'), isNull); // Too short
      expect(AuthSecurityUtils.normalizePhone('abcdef'), isNull);
    });

    test('maskEmail obfuscates email addresses safely', () {
      expect(
        AuthSecurityUtils.maskEmail('john.doe@example.com'),
        equals('j***e@example.com'),
      );
      expect(
        AuthSecurityUtils.maskEmail('me@example.com'),
        equals('m***@example.com'),
      );
    });

    test('maskPhone obfuscates phone numbers safely', () {
      expect(
        AuthSecurityUtils.maskPhone('+14155552671'),
        equals('+14***2671'),
      );
    });

    test('generateSecureToken creates unique URL-safe tokens', () {
      final token1 = AuthSecurityUtils.generateSecureToken(byteLength: 32);
      final token2 = AuthSecurityUtils.generateSecureToken(byteLength: 32);
      expect(token1.isNotEmpty, isTrue);
      expect(token2.isNotEmpty, isTrue);
      expect(token1, isNot(equals(token2)));
    });

    test('generateSecureOtp creates 6-digit numeric codes', () {
      final otp = AuthSecurityUtils.generateSecureOtp(length: 6);
      expect(otp.length, equals(6));
      expect(RegExp(r'^\d{6}$').hasMatch(otp), isTrue);
    });

    test('constantTimeEquals correctly checks equality', () {
      expect(AuthSecurityUtils.constantTimeEquals('hello123', 'hello123'), isTrue);
      expect(AuthSecurityUtils.constantTimeEquals('hello123', 'hello124'), isFalse);
      expect(AuthSecurityUtils.constantTimeEquals('hello', 'helloLonger'), isFalse);
    });

    test('hashSecret creates deterministic HMAC with salt', () {
      const salt = 'random-salt-123';
      final hash1 = AuthSecurityUtils.hashSecret('my-secret-otp', salt);
      final hash2 = AuthSecurityUtils.hashSecret('my-secret-otp', salt);
      final hashDiff = AuthSecurityUtils.hashSecret('other-secret', salt);

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(hashDiff)));
    });

    test('hashPassword salts password and hashes securely', () {
      final salt1 = AuthSecurityUtils.generateSalt();
      final salt2 = AuthSecurityUtils.generateSalt();

      final pHash1 = AuthSecurityUtils.hashPassword('SuperSecret123!', salt1);
      final pHash2 = AuthSecurityUtils.hashPassword('SuperSecret123!', salt1);
      final pHash3 = AuthSecurityUtils.hashPassword('SuperSecret123!', salt2);

      expect(pHash1, equals(pHash2));
      expect(pHash1, isNot(equals(pHash3)));
    });
  });
}
