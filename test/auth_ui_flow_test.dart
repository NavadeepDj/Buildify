import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildify_flutter/models/verification_models.dart';
import 'package:buildify_flutter/pages/auth_page.dart';
import 'package:buildify_flutter/pages/verification_page.dart';
import 'package:buildify_flutter/models/user_model.dart';
import 'package:buildify_flutter/providers/auth_provider.dart';
import 'package:buildify_flutter/services/auth_service.dart';

class FailingAuthService extends AuthService {
  @override
  Future<AuthOperationResult> login({
    required String identifier,
    required String password,
  }) async {
    throw StateError('Database unavailable');
  }

  @override
  Future<AuthOperationResult> signUp({
    required String name,
    required String password,
    String? email,
    String? phone,
    String defaultCountryCode = '+1',
    required AuthMethod method,
  }) async {
    throw StateError('Database unavailable');
  }
}

void main() {
  for (final signup in [false, true]) {
    testWidgets(
      '${signup ? 'Signup' : 'Login'} recovers after an authentication exception',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authServiceProvider.overrideWithValue(FailingAuthService()),
            ],
            child: const MaterialApp(home: AuthPage()),
          ),
        );
        if (signup) {
          await tester.tap(find.text('new to buildify? signup'));
          await tester.pump();
        }
        final fields = find.byType(TextFormField);
        if (signup) await tester.enterText(fields.at(0), 'Test User');
        await tester.enterText(fields.at(signup ? 1 : 0), 'user@example.com');
        await tester.enterText(fields.at(signup ? 2 : 1), 'password123');
        final submit = find.text(signup ? 'verify & signup' : 'login');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(
          find.text('Unable to complete authentication. Please try again.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('AuthPage renders login form by default and toggles to signup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthPage())),
    );
    await tester.pump();

    expect(find.text('welcome back'), findsOneWidget);
    expect(find.text('login'), findsOneWidget);
    expect(find.text('new to buildify? signup'), findsOneWidget);

    // Switch to signup mode
    await tester.tap(find.text('new to buildify? signup'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('create your account'), findsOneWidget);
    expect(find.text('verification method:'), findsOneWidget);
    expect(find.text('Email Link'), findsOneWidget);
    expect(find.text('Phone OTP'), findsOneWidget);
    expect(find.text('verify & signup'), findsOneWidget);
  });

  testWidgets(
    'AuthPage toggles between Email Link and Phone OTP in signup mode',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthPage())),
      );
      await tester.pump();

      // Switch to signup
      await tester.tap(find.text('new to buildify? signup'));
      await tester.pump(const Duration(milliseconds: 300));

      // Default is Email Link
      expect(find.text('email address'), findsOneWidget);
      expect(find.text('phone number'), findsNothing);

      // Tap Phone OTP
      await tester.tap(find.text('Phone OTP'));
      await tester.pump(const Duration(milliseconds: 300));

      // Phone inputs appear
      expect(find.text('phone number'), findsOneWidget);
      expect(find.text('+1 US/CA'), findsOneWidget);
      expect(find.text('email address'), findsNothing);
    },
  );

  testWidgets('VerificationPage renders Phone OTP view with 6-digit input', (
    WidgetTester tester,
  ) async {
    final challenge = ChallengePublicInfo(
      challengeId: 'test-challenge-123',
      userId: 'test-user-123',
      channel: VerificationChannel.phone,
      maskedTarget: '+1415***2671',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      cooldownSeconds: 60,
      attemptsRemaining: 5,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VerificationPage(challenge: challenge)),
      ),
    );
    await tester.pump();

    expect(find.text('enter otp code'), findsOneWidget);
    expect(find.textContaining('+1415***2671'), findsOneWidget);
    expect(find.text('verify code'), findsOneWidget);
    expect(find.textContaining('resend in'), findsOneWidget);
  });

  testWidgets('VerificationPage renders Email verification pending view', (
    WidgetTester tester,
  ) async {
    final challenge = ChallengePublicInfo(
      challengeId: 'test-email-challenge',
      userId: 'test-user-456',
      channel: VerificationChannel.email,
      maskedTarget: 'u***r@example.com',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      cooldownSeconds: 60,
      attemptsRemaining: 5,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VerificationPage(challenge: challenge)),
      ),
    );
    await tester.pump();

    expect(find.text('verify your email'), findsOneWidget);
    expect(find.textContaining('u***r@example.com'), findsOneWidget);
    expect(find.text('verify token'), findsOneWidget);
    expect(
      find.textContaining('paste verification token manually'),
      findsOneWidget,
    );
  });
}
