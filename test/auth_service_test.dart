import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buildify_flutter/models/user_model.dart';
import 'package:buildify_flutter/models/verification_models.dart';
import 'package:buildify_flutter/services/auth_service.dart';
import 'package:buildify_flutter/services/database_helper.dart';
import 'package:buildify_flutter/services/delivery_providers.dart';

class MockEmailDeliveryProvider implements EmailDeliveryProvider {
  bool shouldSucceed = true;
  String? lastRecipient;
  String? lastToken;
  String? lastUrl;

  @override
  Future<DeliveryResult> sendVerificationEmail({
    required String recipientEmail,
    required String verificationUrl,
    required String verificationToken,
    required String userName,
    required Duration expiryDuration,
  }) async {
    lastRecipient = recipientEmail;
    lastToken = verificationToken;
    lastUrl = verificationUrl;
    if (!shouldSucceed) {
      return DeliveryResult.failure('Simulated SMTP connection timeout');
    }
    return DeliveryResult.ok(messageId: 'mock_email_msg_1');
  }
}

class MockSmsDeliveryProvider implements SmsDeliveryProvider {
  bool shouldSucceed = true;
  String? lastRecipient;
  String? lastOtp;

  @override
  Future<DeliveryResult> sendVerificationOtp({
    required String recipientPhone,
    required String otpCode,
    required Duration expiryDuration,
  }) async {
    lastRecipient = recipientPhone;
    lastOtp = otpCode;
    if (!shouldSucceed) {
      return DeliveryResult.failure('Simulated SMS gateway failure');
    }
    return DeliveryResult.ok(messageId: 'mock_sms_msg_1');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper dbHelper;
  late MockEmailDeliveryProvider mockEmail;
  late MockSmsDeliveryProvider mockSms;
  late AuthService authService;

  setUp(() async {
    dbHelper = DatabaseHelper.instance;
    await dbHelper.clearAll();
    mockEmail = MockEmailDeliveryProvider();
    mockSms = MockSmsDeliveryProvider();
    authService = AuthService(
      dbHelper: dbHelper,
      emailProvider: mockEmail,
      smsProvider: mockSms,
    );
  });

  group('AuthService - Email Verification Flow', () {
    test('Successful signup sends email verification link with secure token', () async {
      final result = await authService.signUp(
        name: 'Alice Dev',
        email: 'alice@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      expect(result.status, equals(AuthStatus.pendingVerification));
      expect(result.challenge, isNotNull);
      expect(result.challenge!.channel, equals(VerificationChannel.email));
      expect(result.challenge!.maskedTarget, equals('a***e@example.com'));

      // Check provider call
      expect(mockEmail.lastRecipient, equals('alice@example.com'));
      expect(mockEmail.lastToken, isNotNull);
      expect(mockEmail.lastUrl, contains(mockEmail.lastToken!));

      // User in database is unverified initially
      final user = await dbHelper.getUserByEmail('alice@example.com');
      expect(user, isNotNull);
      expect(user!['email_verified'], equals(0));
    });

    test('Valid email token verifies user atomically', () async {
      await authService.signUp(
        name: 'Alice Dev',
        email: 'alice@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      final token = mockEmail.lastToken!;
      final verifyResult = await authService.verifyEmailToken(token);

      expect(verifyResult.status, equals(AuthStatus.success));
      final verifiedUser = verifyResult.user as User;
      expect(verifiedUser.emailVerified, isTrue);
      expect(verifiedUser.isVerified, isTrue);

      // Verify database updated persistently
      final dbUser = await dbHelper.getUserByEmail('alice@example.com');
      expect(dbUser!['email_verified'], equals(1));
    });

    test('Invalid or tampering with email token is rejected', () async {
      await authService.signUp(
        name: 'Bob Dev',
        email: 'bob@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      final verifyResult = await authService.verifyEmailToken('fake-invalid-token');
      expect(verifyResult.status, equals(AuthStatus.invalidToken));

      final dbUser = await dbHelper.getUserByEmail('bob@example.com');
      expect(dbUser!['email_verified'], equals(0));
    });

    test('Reusing an already consumed email token is rejected', () async {
      await authService.signUp(
        name: 'Charlie Dev',
        email: 'charlie@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      final token = mockEmail.lastToken!;
      final firstVerify = await authService.verifyEmailToken(token);
      expect(firstVerify.status, equals(AuthStatus.success));

      // Re-use attempt
      final secondVerify = await authService.verifyEmailToken(token);
      expect(secondVerify.status, equals(AuthStatus.invalidToken));
      expect(secondVerify.message, contains('already been used'));
    });

    test('Email provider failure rejects signup and does not verify user', () async {
      mockEmail.shouldSucceed = false;

      final result = await authService.signUp(
        name: 'Failure Test',
        email: 'fail@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      expect(result.status, equals(AuthStatus.deliveryFailed));
      final user = await dbHelper.getUserByEmail('fail@example.com');
      expect(user!['email_verified'], equals(0));
    });
  });

  group('AuthService - Phone OTP Verification Flow', () {
    test('Successful signup sends 6-digit OTP code to phone number', () async {
      final result = await authService.signUp(
        name: 'David Phone',
        phone: '4155552671',
        defaultCountryCode: '+1',
        password: 'password123',
        method: AuthMethod.phone,
      );

      expect(result.status, equals(AuthStatus.pendingVerification));
      expect(result.challenge, isNotNull);
      expect(result.challenge!.channel, equals(VerificationChannel.phone));
      expect(result.challenge!.maskedTarget, contains('2671'));

      // Check provider call
      expect(mockSms.lastRecipient, equals('+14155552671'));
      expect(mockSms.lastOtp, isNotNull);
      expect(mockSms.lastOtp!.length, equals(6));

      // User is initially unverified
      final user = await dbHelper.getUserByPhone('+14155552671');
      expect(user!['phone_verified'], equals(0));
    });

    test('Valid OTP code verifies phone number and marks challenge consumed', () async {
      final signupResult = await authService.signUp(
        name: 'David Phone',
        phone: '4155552671',
        defaultCountryCode: '+1',
        password: 'password123',
        method: AuthMethod.phone,
      );

      final challengeId = signupResult.challenge!.challengeId;
      final otp = mockSms.lastOtp!;

      final verifyResult = await authService.verifyPhoneOtp(
        challengeId: challengeId,
        rawOtp: otp,
      );

      expect(verifyResult.status, equals(AuthStatus.success));
      final verifiedUser = verifyResult.user as User;
      expect(verifiedUser.phoneVerified, isTrue);

      final dbUser = await dbHelper.getUserByPhone('+14155552671');
      expect(dbUser!['phone_verified'], equals(1));
    });

    test('Incorrect OTP increments attempt count and enforces lockout after max attempts', () async {
      final signupResult = await authService.signUp(
        name: 'Emma Phone',
        phone: '4155559999',
        defaultCountryCode: '+1',
        password: 'password123',
        method: AuthMethod.phone,
      );

      final challengeId = signupResult.challenge!.challengeId;

      // Send 4 wrong attempts
      for (int i = 0; i < 4; i++) {
        final res = await authService.verifyPhoneOtp(
          challengeId: challengeId,
          rawOtp: '000000',
        );
        expect(res.status, equals(AuthStatus.invalidCredentials));
        expect(res.message, contains('remaining'));
      }

      // 5th wrong attempt locks the code
      final lockRes = await authService.verifyPhoneOtp(
        challengeId: challengeId,
        rawOtp: '000000',
      );
      expect(lockRes.status, equals(AuthStatus.rateLimited));
      expect(lockRes.message, contains('locked'));

      // Even correct OTP is now rejected because it's locked
      final correctOtp = mockSms.lastOtp!;
      final afterLock = await authService.verifyPhoneOtp(
        challengeId: challengeId,
        rawOtp: correctOtp,
      );
      expect(afterLock.status, equals(AuthStatus.rateLimited));
    });

    test('Reusing consumed OTP is rejected', () async {
      final signupResult = await authService.signUp(
        name: 'Frank Phone',
        phone: '4155558888',
        defaultCountryCode: '+1',
        password: 'password123',
        method: AuthMethod.phone,
      );

      final challengeId = signupResult.challenge!.challengeId;
      final otp = mockSms.lastOtp!;

      final firstRes = await authService.verifyPhoneOtp(
        challengeId: challengeId,
        rawOtp: otp,
      );
      expect(firstRes.status, equals(AuthStatus.success));

      final secondRes = await authService.verifyPhoneOtp(
        challengeId: challengeId,
        rawOtp: otp,
      );
      expect(secondRes.status, equals(AuthStatus.invalidToken));
      expect(secondRes.message, contains('already been used'));
    });

    test('SMS provider failure returns deliveryFailed and preserves unverified status', () async {
      mockSms.shouldSucceed = false;

      final result = await authService.signUp(
        name: 'SMS Fail',
        phone: '4155557777',
        defaultCountryCode: '+1',
        password: 'password123',
        method: AuthMethod.phone,
      );

      expect(result.status, equals(AuthStatus.deliveryFailed));
      final user = await dbHelper.getUserByPhone('+14155557777');
      expect(user!['phone_verified'], equals(0));
    });
  });

  group('AuthService - Resend Cooldowns & Rate Limiting', () {
    test('Resend before cooldown period expires is rejected', () async {
      final signupResult = await authService.signUp(
        name: 'Grace Test',
        email: 'grace@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      final challengeId = signupResult.challenge!.challengeId;

      // Immediate resend should be blocked by cooldown
      final resendResult = await authService.resendVerification(
        challengeId: challengeId,
      );

      expect(resendResult.status, equals(AuthStatus.rateLimited));
      expect(resendResult.message, contains('Please wait'));
    });
  });

  group('AuthService - Login & Access Control', () {
    test('Login with unverified account is intercepted and requires verification', () async {
      await authService.signUp(
        name: 'Unverified User',
        email: 'unverified@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      final loginResult = await authService.login(
        identifier: 'unverified@example.com',
        password: 'password123',
      );

      expect(loginResult.status, equals(AuthStatus.pendingVerification));
      expect(loginResult.challenge, isNotNull);
    });

    test('Login with verified account succeeds and provides access', () async {
      await authService.signUp(
        name: 'Verified User',
        email: 'verified@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      await authService.verifyEmailToken(mockEmail.lastToken!);

      final loginResult = await authService.login(
        identifier: 'verified@example.com',
        password: 'password123',
      );

      expect(loginResult.status, equals(AuthStatus.success));
      final user = loginResult.user as User;
      expect(user.emailVerified, isTrue);
    });

    test('Login with incorrect password fails', () async {
      await authService.signUp(
        name: 'Test Login',
        email: 'login@example.com',
        password: 'correctPassword123',
        method: AuthMethod.email,
      );

      final loginResult = await authService.login(
        identifier: 'login@example.com',
        password: 'wrongPassword123',
      );

      expect(loginResult.status, equals(AuthStatus.invalidCredentials));
    });

    test('Duplicate signup for verified account is prevented safely', () async {
      await authService.signUp(
        name: 'Original',
        email: 'duplicate@example.com',
        password: 'password123',
        method: AuthMethod.email,
      );

      await authService.verifyEmailToken(mockEmail.lastToken!);

      // Duplicate signup
      final dupResult = await authService.signUp(
        name: 'Imposter',
        email: 'duplicate@example.com',
        password: 'newPassword123',
        method: AuthMethod.email,
      );

      expect(dupResult.status, equals(AuthStatus.accountExists));
    });
  });
}
