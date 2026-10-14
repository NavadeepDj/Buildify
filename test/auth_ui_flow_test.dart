import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildify/models/verification_models.dart';
import 'package:buildify/pages/auth_page.dart';
import 'package:buildify/pages/verification_page.dart';

void main() {
  testWidgets('AuthPage renders login form by default and toggles to signup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthPage()),
      ),
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

  testWidgets('AuthPage toggles between Email Link and Phone OTP in signup mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthPage()),
      ),
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
  });

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
        child: MaterialApp(
          home: VerificationPage(challenge: challenge),
        ),
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
        child: MaterialApp(
          home: VerificationPage(challenge: challenge),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('verify your email'), findsOneWidget);
    expect(find.textContaining('u***r@example.com'), findsOneWidget);
    expect(find.text('verify token'), findsOneWidget);
    expect(find.textContaining('paste verification token manually'), findsOneWidget);
  });
}
