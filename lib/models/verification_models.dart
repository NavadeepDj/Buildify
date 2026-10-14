enum VerificationChannel { email, phone }

class VerificationChallenge {
  const VerificationChallenge({
    required this.id,
    required this.userId,
    required this.channel,
    required this.target,
    required this.secretHash,
    required this.salt,
    required this.expiresAt,
    this.consumedAt,
    this.attempts = 0,
    this.maxAttempts = 5,
    this.resendCount = 0,
    required this.lastSentAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final VerificationChannel channel;
  final String target;
  final String secretHash;
  final String salt;
  final DateTime expiresAt;
  final DateTime? consumedAt;
  final int attempts;
  final int maxAttempts;
  final int resendCount;
  final DateTime lastSentAt;
  final DateTime createdAt;

  bool get isConsumed => consumedAt != null;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isLocked => attempts >= maxAttempts;
  bool get isValid => !isConsumed && !isExpired && !isLocked;

  VerificationChallenge copyWith({
    String? secretHash,
    String? salt,
    DateTime? expiresAt,
    DateTime? consumedAt,
    int? attempts,
    int? maxAttempts,
    int? resendCount,
    DateTime? lastSentAt,
  }) {
    return VerificationChallenge(
      id: id,
      userId: userId,
      channel: channel,
      target: target,
      secretHash: secretHash ?? this.secretHash,
      salt: salt ?? this.salt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt ?? this.consumedAt,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      resendCount: resendCount ?? this.resendCount,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'channel': channel.name,
      'target': target,
      'secret_hash': secretHash,
      'salt': salt,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'consumed_at': consumedAt?.millisecondsSinceEpoch,
      'attempts': attempts,
      'max_attempts': maxAttempts,
      'resend_count': resendCount,
      'last_sent_at': lastSentAt.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory VerificationChallenge.fromMap(Map<String, dynamic> map) {
    return VerificationChallenge(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      channel: (map['channel'] as String) == 'phone'
          ? VerificationChannel.phone
          : VerificationChannel.email,
      target: map['target'] as String,
      secretHash: map['secret_hash'] as String,
      salt: map['salt'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int),
      consumedAt: map['consumed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['consumed_at'] as int)
          : null,
      attempts: map['attempts'] as int? ?? 0,
      maxAttempts: map['max_attempts'] as int? ?? 5,
      resendCount: map['resend_count'] as int? ?? 0,
      lastSentAt: DateTime.fromMillisecondsSinceEpoch(map['last_sent_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// Safe public challenge view passed to UI / client without exposing secretHash or salt
class ChallengePublicInfo {
  const ChallengePublicInfo({
    required this.challengeId,
    required this.userId,
    required this.channel,
    required this.maskedTarget,
    required this.expiresAt,
    required this.cooldownSeconds,
    required this.attemptsRemaining,
  });

  final String challengeId;
  final String userId;
  final VerificationChannel channel;
  final String maskedTarget;
  final DateTime expiresAt;
  final int cooldownSeconds;
  final int attemptsRemaining;
}

enum AuthStatus {
  success,
  pendingVerification,
  invalidCredentials,
  accountExists,
  expired,
  invalidToken,
  rateLimited,
  deliveryFailed,
  error,
}

class AuthOperationResult {
  const AuthOperationResult({
    required this.status,
    required this.message,
    this.challenge,
    this.user,
  });

  final AuthStatus status;
  final String message;
  final ChallengePublicInfo? challenge;
  final dynamic user;

  bool get isSuccess => status == AuthStatus.success;
}
