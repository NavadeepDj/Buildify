import 'dart:async';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../models/verification_models.dart';
import 'auth_security_utils.dart';
import 'database_helper.dart';
import 'delivery_providers.dart';

class AuthService {
  AuthService({
    DatabaseHelper? dbHelper,
    EmailDeliveryProvider? emailProvider,
    SmsDeliveryProvider? smsProvider,
    String? appBaseUrl,
  })  : _db = dbHelper ?? DatabaseHelper.instance,
        _emailProvider = emailProvider ?? ConfiguredEmailProvider(),
        _smsProvider = smsProvider ?? ConfiguredSmsProvider(),
        _appBaseUrl = appBaseUrl ?? 'https://buildify.me';

  final DatabaseHelper _db;
  final EmailDeliveryProvider _emailProvider;
  final SmsDeliveryProvider _smsProvider;
  final String _appBaseUrl;
  final _uuid = const Uuid();

  // Configuration constants
  static const Duration emailTokenLifetime = Duration(minutes: 30);
  static const Duration smsOtpLifetime = Duration(minutes: 5);
  static const Duration resendCooldown = Duration(seconds: 60);
  static const int maxOtpAttempts = 5;
  static const int maxResends = 5;

  /// Registers a new user with chosen verification method (email or phone).
  Future<AuthOperationResult> signUp({
    required String name,
    required String password,
    String? email,
    String? phone,
    String defaultCountryCode = '+1',
    required AuthMethod method,
  }) async {
    // 1. Validate name & password
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const AuthOperationResult(
        status: AuthStatus.error,
        message: 'Display name is required.',
      );
    }
    if (password.length < 8) {
      return const AuthOperationResult(
        status: AuthStatus.error,
        message: 'Password must be at least 8 characters long.',
      );
    }

    // 2. Validate & normalize target
    String? normalizedEmail;
    String? normalizedPhone;

    if (method == AuthMethod.email) {
      normalizedEmail = AuthSecurityUtils.normalizeEmail(email);
      if (normalizedEmail == null) {
        return const AuthOperationResult(
          status: AuthStatus.error,
          message: 'Please enter a valid email address.',
        );
      }
    } else {
      normalizedPhone = AuthSecurityUtils.normalizePhone(
        phone,
        defaultCountryCode: defaultCountryCode,
      );
      if (normalizedPhone == null) {
        return const AuthOperationResult(
          status: AuthStatus.error,
          message: 'Please enter a valid phone number with country code.',
        );
      }
    }

    // 3. Check for existing accounts
    Map<String, dynamic>? existingRow;
    if (method == AuthMethod.email && normalizedEmail != null) {
      existingRow = await _db.getUserByEmail(normalizedEmail);
    } else if (method == AuthMethod.phone && normalizedPhone != null) {
      existingRow = await _db.getUserByPhone(normalizedPhone);
    }

    User? user;
    if (existingRow != null) {
      final existingUser = User.fromMap(existingRow);
      if (existingUser.isVerified) {
        return const AuthOperationResult(
          status: AuthStatus.accountExists,
          message: 'An account with this contact information already exists.',
        );
      }
      // If user exists but is unverified, update name and credentials to allow re-signup
      final salt = AuthSecurityUtils.generateSalt();
      final passwordHash = AuthSecurityUtils.hashPassword(password, salt);
      user = existingUser.copyWith(
        name: trimmedName,
        passwordHash: passwordHash,
        passwordSalt: salt,
        updatedAt: DateTime.now(),
      );
      await _db.updateUser(user.id, user.toMap());
    } else {
      // Create new user
      final salt = AuthSecurityUtils.generateSalt();
      final passwordHash = AuthSecurityUtils.hashPassword(password, salt);
      final now = DateTime.now();
      user = User(
        id: _uuid.v4(),
        name: trimmedName,
        email: normalizedEmail,
        phone: normalizedPhone,
        passwordHash: passwordHash,
        passwordSalt: salt,
        authMethod: method,
        emailVerified: false,
        phoneVerified: false,
        createdAt: now,
        updatedAt: now,
      );
      await _db.insertUser(user.toMap());
    }

    // 4. Create and dispatch challenge
    return await _createAndSendChallenge(user);
  }

  /// Internal helper to generate challenge secret, hash it, store, and dispatch
  Future<AuthOperationResult> _createAndSendChallenge(User user) async {
    final now = DateTime.now();
    final challengeId = _uuid.v4();
    final salt = AuthSecurityUtils.generateSalt();

    if (user.authMethod == AuthMethod.email) {
      final target = user.email!;
      final token = AuthSecurityUtils.generateSecureToken(byteLength: 32);
      final secretHash = AuthSecurityUtils.hashSecret(token, salt);
      final expiresAt = now.add(emailTokenLifetime);

      final challenge = VerificationChallenge(
        id: challengeId,
        userId: user.id,
        channel: VerificationChannel.email,
        target: target,
        secretHash: secretHash,
        salt: salt,
        expiresAt: expiresAt,
        lastSentAt: now,
        createdAt: now,
      );

      await _db.insertChallenge(challenge.toMap());

      // Send actual email
      final verificationUrl = '$_appBaseUrl/verify?token=$token';
      final delivery = await _emailProvider.sendVerificationEmail(
        recipientEmail: target,
        verificationUrl: verificationUrl,
        verificationToken: token,
        userName: user.name,
        expiryDuration: emailTokenLifetime,
      );

      if (!delivery.success) {
        return AuthOperationResult(
          status: AuthStatus.deliveryFailed,
          message: delivery.errorMessage ?? 'Failed to deliver verification email.',
        );
      }

      final publicInfo = ChallengePublicInfo(
        challengeId: challengeId,
        userId: user.id,
        channel: VerificationChannel.email,
        maskedTarget: AuthSecurityUtils.maskEmail(target),
        expiresAt: expiresAt,
        cooldownSeconds: resendCooldown.inSeconds,
        attemptsRemaining: maxOtpAttempts,
      );

      return AuthOperationResult(
        status: AuthStatus.pendingVerification,
        message: 'A verification link has been sent to ${AuthSecurityUtils.maskEmail(target)}.',
        challenge: publicInfo,
        user: user,
      );
    } else {
      final target = user.phone!;
      final otp = AuthSecurityUtils.generateSecureOtp(length: 6);
      final secretHash = AuthSecurityUtils.hashSecret(otp, salt);
      final expiresAt = now.add(smsOtpLifetime);

      final challenge = VerificationChallenge(
        id: challengeId,
        userId: user.id,
        channel: VerificationChannel.phone,
        target: target,
        secretHash: secretHash,
        salt: salt,
        expiresAt: expiresAt,
        lastSentAt: now,
        createdAt: now,
      );

      await _db.insertChallenge(challenge.toMap());

      // Send actual SMS OTP
      final delivery = await _smsProvider.sendVerificationOtp(
        recipientPhone: target,
        otpCode: otp,
        expiryDuration: smsOtpLifetime,
      );

      if (!delivery.success) {
        return AuthOperationResult(
          status: AuthStatus.deliveryFailed,
          message: delivery.errorMessage ?? 'Failed to deliver SMS verification code.',
        );
      }

      final publicInfo = ChallengePublicInfo(
        challengeId: challengeId,
        userId: user.id,
        channel: VerificationChannel.phone,
        maskedTarget: AuthSecurityUtils.maskPhone(target),
        expiresAt: expiresAt,
        cooldownSeconds: resendCooldown.inSeconds,
        attemptsRemaining: maxOtpAttempts,
      );

      return AuthOperationResult(
        status: AuthStatus.pendingVerification,
        message: 'A 6-digit verification code was sent to ${AuthSecurityUtils.maskPhone(target)}.',
        challenge: publicInfo,
        user: user,
      );
    }
  }

  /// Verifies an email token sent via email link or manual entry.
  Future<AuthOperationResult> verifyEmailToken(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'Verification token cannot be empty.',
      );
    }

    // Query active unconsumed email challenges
    final now = DateTime.now();
    final db = await _db.database;
    final rows = await db.query(
      'verification_challenges',
      where: 'channel = ?',
      whereArgs: ['email'],
      orderBy: 'created_at DESC',
    );

    VerificationChallenge? matchedChallenge;
    for (final row in rows) {
      final challenge = VerificationChallenge.fromMap(row);
      final calculatedHash = AuthSecurityUtils.hashSecret(token, challenge.salt);
      if (AuthSecurityUtils.constantTimeEquals(calculatedHash, challenge.secretHash)) {
        matchedChallenge = challenge;
        break;
      }
    }

    if (matchedChallenge == null) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'Invalid verification token.',
      );
    }

    if (matchedChallenge.isConsumed) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'This verification token has already been used.',
      );
    }

    if (matchedChallenge.isExpired) {
      return const AuthOperationResult(
        status: AuthStatus.expired,
        message: 'This verification token has expired. Please request a new one.',
      );
    }

    // Atomically mark challenge as consumed and user as verified
    await _db.updateChallenge(matchedChallenge.id, {
      'consumed_at': now.millisecondsSinceEpoch,
    });

    final userRow = await _db.getUserById(matchedChallenge.userId);
    if (userRow == null) {
      return const AuthOperationResult(
        status: AuthStatus.error,
        message: 'User account not found.',
      );
    }

    await _db.updateUser(matchedChallenge.userId, {
      'email_verified': 1,
      'updated_at': now.millisecondsSinceEpoch,
    });

    final updatedUserMap = await _db.getUserById(matchedChallenge.userId);
    final updatedUser = User.fromMap(updatedUserMap!);
    return AuthOperationResult(
      status: AuthStatus.success,
      message: 'Email verified successfully!',
      user: updatedUser,
    );
  }

  /// Verifies a 6-digit SMS OTP against a challenge ID.
  Future<AuthOperationResult> verifyPhoneOtp({
    required String challengeId,
    required String rawOtp,
  }) async {
    final otp = rawOtp.trim();
    if (otp.isEmpty || otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      return const AuthOperationResult(
        status: AuthStatus.error,
        message: 'Please enter a valid 6-digit code.',
      );
    }

    final challengeRow = await _db.getChallenge(challengeId);
    if (challengeRow == null) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'Verification challenge not found.',
      );
    }

    final challenge = VerificationChallenge.fromMap(challengeRow);
    if (challenge.channel != VerificationChannel.phone) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'Invalid verification method.',
      );
    }

    if (challenge.isConsumed) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'This verification code has already been used.',
      );
    }

    if (challenge.isExpired) {
      return const AuthOperationResult(
        status: AuthStatus.expired,
        message: 'This verification code has expired. Please request a new one.',
      );
    }

    if (challenge.isLocked) {
      return const AuthOperationResult(
        status: AuthStatus.rateLimited,
        message: 'Too many incorrect attempts. Please request a new code.',
      );
    }

    // Verify OTP with constant-time equality check
    final computedHash = AuthSecurityUtils.hashSecret(otp, challenge.salt);
    final isMatch = AuthSecurityUtils.constantTimeEquals(computedHash, challenge.secretHash);

    if (!isMatch) {
      final newAttempts = challenge.attempts + 1;
      await _db.updateChallenge(challenge.id, {
        'attempts': newAttempts,
      });

      final remaining = challenge.maxAttempts - newAttempts;
      if (remaining <= 0) {
        return const AuthOperationResult(
          status: AuthStatus.rateLimited,
          message: 'Code locked after too many attempts. Please request a new code.',
        );
      }

      return AuthOperationResult(
        status: AuthStatus.invalidCredentials,
        message: 'Incorrect verification code. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
      );
    }

    // Success: mark challenge consumed and user verified
    final now = DateTime.now();
    await _db.updateChallenge(challenge.id, {
      'consumed_at': now.millisecondsSinceEpoch,
    });

    await _db.updateUser(challenge.userId, {
      'phone_verified': 1,
      'updated_at': now.millisecondsSinceEpoch,
    });

    final updatedUserMap = await _db.getUserById(challenge.userId);
    final updatedUser = User.fromMap(updatedUserMap!);
    return AuthOperationResult(
      status: AuthStatus.success,
      message: 'Phone number verified successfully!',
      user: updatedUser,
    );
  }

  /// Resends a verification token or OTP with cooldown and rate limit enforcement.
  Future<AuthOperationResult> resendVerification({
    required String challengeId,
  }) async {
    final challengeRow = await _db.getChallenge(challengeId);
    if (challengeRow == null) {
      return const AuthOperationResult(
        status: AuthStatus.invalidToken,
        message: 'Verification challenge not found.',
      );
    }

    final oldChallenge = VerificationChallenge.fromMap(challengeRow);
    final now = DateTime.now();

    // Check cooldown
    final timeSinceLastSent = now.difference(oldChallenge.lastSentAt);
    if (timeSinceLastSent < resendCooldown) {
      final remaining = (resendCooldown - timeSinceLastSent).inSeconds;
      return AuthOperationResult(
        status: AuthStatus.rateLimited,
        message: 'Please wait $remaining seconds before requesting another code.',
      );
    }

    // Check hourly limit
    if (oldChallenge.resendCount >= maxResends) {
      return const AuthOperationResult(
        status: AuthStatus.rateLimited,
        message: 'Maximum resend attempts reached. Please try again later.',
      );
    }

    // Mark previous challenge as superseded/consumed
    await _db.updateChallenge(oldChallenge.id, {
      'consumed_at': now.millisecondsSinceEpoch,
    });

    final userRow = await _db.getUserById(oldChallenge.userId);
    if (userRow == null) {
      return const AuthOperationResult(
        status: AuthStatus.error,
        message: 'User account not found.',
      );
    }
    final user = User.fromMap(userRow);

    // Create fresh challenge
    final newChallengeId = _uuid.v4();
    final newSalt = AuthSecurityUtils.generateSalt();
    final newResendCount = oldChallenge.resendCount + 1;

    if (oldChallenge.channel == VerificationChannel.email) {
      final newToken = AuthSecurityUtils.generateSecureToken(byteLength: 32);
      final newHash = AuthSecurityUtils.hashSecret(newToken, newSalt);
      final expiresAt = now.add(emailTokenLifetime);

      final newChallenge = VerificationChallenge(
        id: newChallengeId,
        userId: user.id,
        channel: VerificationChannel.email,
        target: user.email!,
        secretHash: newHash,
        salt: newSalt,
        expiresAt: expiresAt,
        resendCount: newResendCount,
        lastSentAt: now,
        createdAt: now,
      );

      await _db.insertChallenge(newChallenge.toMap());

      final verificationUrl = '$_appBaseUrl/verify?token=$newToken';
      final delivery = await _emailProvider.sendVerificationEmail(
        recipientEmail: user.email!,
        verificationUrl: verificationUrl,
        verificationToken: newToken,
        userName: user.name,
        expiryDuration: emailTokenLifetime,
      );

      if (!delivery.success) {
        return AuthOperationResult(
          status: AuthStatus.deliveryFailed,
          message: delivery.errorMessage ?? 'Failed to resend verification email.',
        );
      }

      final publicInfo = ChallengePublicInfo(
        challengeId: newChallengeId,
        userId: user.id,
        channel: VerificationChannel.email,
        maskedTarget: AuthSecurityUtils.maskEmail(user.email!),
        expiresAt: expiresAt,
        cooldownSeconds: resendCooldown.inSeconds,
        attemptsRemaining: maxOtpAttempts,
      );

      return AuthOperationResult(
        status: AuthStatus.pendingVerification,
        message: 'A new verification link was sent to ${AuthSecurityUtils.maskEmail(user.email!)}.',
        challenge: publicInfo,
        user: user,
      );
    } else {
      final newOtp = AuthSecurityUtils.generateSecureOtp(length: 6);
      final newHash = AuthSecurityUtils.hashSecret(newOtp, newSalt);
      final expiresAt = now.add(smsOtpLifetime);

      final newChallenge = VerificationChallenge(
        id: newChallengeId,
        userId: user.id,
        channel: VerificationChannel.phone,
        target: user.phone!,
        secretHash: newHash,
        salt: newSalt,
        expiresAt: expiresAt,
        resendCount: newResendCount,
        lastSentAt: now,
        createdAt: now,
      );

      await _db.insertChallenge(newChallenge.toMap());

      final delivery = await _smsProvider.sendVerificationOtp(
        recipientPhone: user.phone!,
        otpCode: newOtp,
        expiryDuration: smsOtpLifetime,
      );

      if (!delivery.success) {
        return AuthOperationResult(
          status: AuthStatus.deliveryFailed,
          message: delivery.errorMessage ?? 'Failed to resend verification code.',
        );
      }

      final publicInfo = ChallengePublicInfo(
        challengeId: newChallengeId,
        userId: user.id,
        channel: VerificationChannel.phone,
        maskedTarget: AuthSecurityUtils.maskPhone(user.phone!),
        expiresAt: expiresAt,
        cooldownSeconds: resendCooldown.inSeconds,
        attemptsRemaining: maxOtpAttempts,
      );

      return AuthOperationResult(
        status: AuthStatus.pendingVerification,
        message: 'A new code was sent to ${AuthSecurityUtils.maskPhone(user.phone!)}.',
        challenge: publicInfo,
        user: user,
      );
    }
  }

  /// Authenticates an existing user and checks verified status.
  Future<AuthOperationResult> login({
    required String identifier,
    required String password,
  }) async {
    final trimmedIdentifier = identifier.trim();
    if (trimmedIdentifier.isEmpty || password.isEmpty) {
      return const AuthOperationResult(
        status: AuthStatus.invalidCredentials,
        message: 'Please provide both username/email/phone and password.',
      );
    }

    final userRow = await _db.getUserByIdentifier(trimmedIdentifier);
    if (userRow == null) {
      return const AuthOperationResult(
        status: AuthStatus.invalidCredentials,
        message: 'Invalid credentials.',
      );
    }

    final user = User.fromMap(userRow);
    final computedHash = AuthSecurityUtils.hashPassword(password, user.passwordSalt);
    if (!AuthSecurityUtils.constantTimeEquals(computedHash, user.passwordHash)) {
      return const AuthOperationResult(
        status: AuthStatus.invalidCredentials,
        message: 'Invalid credentials.',
      );
    }

    // Check verification status
    if (!user.isVerified) {
      // Find or initiate active challenge for user
      final activeChallenges = await _db.getActiveChallengesForUser(
        user.id,
        user.authMethod == AuthMethod.email ? 'email' : 'phone',
      );

      ChallengePublicInfo? publicInfo;
      if (activeChallenges.isNotEmpty) {
        final ch = VerificationChallenge.fromMap(activeChallenges.first);
        final maskedTarget = user.authMethod == AuthMethod.email
            ? AuthSecurityUtils.maskEmail(user.email ?? '')
            : AuthSecurityUtils.maskPhone(user.phone ?? '');

        publicInfo = ChallengePublicInfo(
          challengeId: ch.id,
          userId: user.id,
          channel: ch.channel,
          maskedTarget: maskedTarget,
          expiresAt: ch.expiresAt,
          cooldownSeconds: resendCooldown.inSeconds,
          attemptsRemaining: ch.maxAttempts - ch.attempts,
        );
      }

      return AuthOperationResult(
        status: AuthStatus.pendingVerification,
        message: 'Your account is not verified yet. Please complete verification.',
        challenge: publicInfo,
        user: user,
      );
    }

    return AuthOperationResult(
      status: AuthStatus.success,
      message: 'Login successful.',
      user: user,
    );
  }

  /// Fetches user by ID
  Future<User?> getUser(String id) async {
    final map = await _db.getUserById(id);
    if (map == null) return null;
    return User.fromMap(map);
  }
}
