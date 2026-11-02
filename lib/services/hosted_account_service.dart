import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class HostedAccount {
  const HostedAccount({
    required this.id,
    required this.email,
    required this.name,
  });
  final String id;
  final String email;
  final String name;
}

class AccountResult {
  const AccountResult({this.needsVerification = false});
  final bool needsVerification;
}

class AccountFailure implements Exception {
  const AccountFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class AccountService {
  bool get isConfigured;
  HostedAccount? get currentAccount;
  Stream<HostedAccount?> get accountChanges;
  Future<AccountResult> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<AccountResult> signIn({
    required String email,
    required String password,
  });
  Future<void> verifyEmail({required String email, required String code});
  Future<void> resendVerification(String email);
  Future<void> signOut();
}

class HostedAccountService implements AccountService {
  HostedAccountService(this.client);
  final sb.SupabaseClient? client;

  @override
  bool get isConfigured => client != null;

  HostedAccount? _account(sb.Session? session) {
    if (session == null ||
        session.isExpired ||
        session.user.emailConfirmedAt == null) {
      return null;
    }
    final user = session.user;
    final displayName = user.userMetadata?['display_name'];
    return HostedAccount(
      id: user.id,
      email: user.email ?? '',
      name:
          displayName is String && displayName.trim().isNotEmpty
              ? displayName
              : user.email ?? 'Buildify user',
    );
  }

  @override
  HostedAccount? get currentAccount => _account(client?.auth.currentSession);

  @override
  Stream<HostedAccount?> get accountChanges async* {
    yield currentAccount;
    final activeClient = client;
    if (activeClient != null) {
      yield* activeClient.auth.onAuthStateChange.map(
        (event) => _account(event.session),
      );
    }
  }

  Future<T> _request<T>(
    Future<T> Function(sb.GoTrueClient auth) operation,
  ) async {
    final activeClient = client;
    if (activeClient == null) {
      throw const AccountFailure(
        'Account sign-in is unavailable in this build. You can continue with local hosting.',
      );
    }
    try {
      return await operation(
        activeClient.auth,
      ).timeout(const Duration(seconds: 25));
    } on sb.AuthException catch (error) {
      throw AccountFailure(switch (error.code) {
        'invalid_credentials' =>
          'Email or password is incorrect. Existing local accounts need a new cloud signup.',
        'user_already_exists' || 'email_exists' =>
          'An account already exists for this email. Try signing in.',
        'email_address_not_authorized' =>
          'Email delivery is not enabled for this address yet. Contact the Buildify administrator.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Too many requests. Please wait before trying again.',
        'otp_expired' || 'otp_disabled' =>
          'This code is invalid or expired. Request a new verification email.',
        'weak_password' =>
          'Choose a stronger password with at least 8 characters.',
        _ =>
          'The account service could not complete this request. Please try again.',
      });
    } on AccountFailure {
      rethrow;
    } catch (_) {
      throw const AccountFailure(
        'Could not reach the account service. Check your connection and try again.',
      );
    }
  }

  @override
  Future<AccountResult> signUp({
    required String name,
    required String email,
    required String password,
  }) => _request((auth) async {
    if (name.trim().isEmpty || password.length < 8) {
      throw const AccountFailure(
        'Enter a display name and a password of at least 8 characters.',
      );
    }
    final response = await auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'display_name': name.trim()},
    );
    return AccountResult(needsVerification: _account(response.session) == null);
  });

  @override
  Future<AccountResult> signIn({
    required String email,
    required String password,
  }) => _request((auth) async {
    try {
      final response = await auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (_account(response.session) == null) {
        return const AccountResult(needsVerification: true);
      }
      return const AccountResult();
    } on sb.AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        return const AccountResult(needsVerification: true);
      }
      rethrow;
    }
  });

  @override
  Future<void> verifyEmail({
    required String email,
    required String code,
  }) => _request((auth) async {
    if (!RegExp(r'^\d{6,10}$').hasMatch(code.trim())) {
      throw const AccountFailure(
        'Enter the verification code from your email.',
      );
    }
    final response = await auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: code.trim(),
      type: sb.OtpType.email,
    );
    if (_account(response.session) == null) {
      throw const AccountFailure(
        'Verification did not establish a confirmed session. Try signing in again.',
      );
    }
  });

  @override
  Future<void> resendVerification(String email) => _request((auth) async {
    await auth.resend(
      type: sb.OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  });

  @override
  Future<void> signOut() =>
      _request((auth) => auth.signOut(scope: sb.SignOutScope.local));
}
