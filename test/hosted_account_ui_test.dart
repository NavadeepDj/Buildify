import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildify_flutter/pages/hosted_account_page.dart';
import 'package:buildify_flutter/providers/hosted_account_provider.dart';
import 'package:buildify_flutter/services/hosted_account_service.dart';

class FakeAccountService implements AccountService {
  FakeAccountService({this.isConfigured = true, this.currentAccount});
  final changes = StreamController<HostedAccount?>.broadcast();
  @override
  final bool isConfigured;
  @override
  HostedAccount? currentAccount;
  bool failLogin = false;
  int loginCalls = 0;
  int verificationCalls = 0;
  int resendCalls = 0;
  Completer<AccountResult>? pendingLogin;
  @override
  Stream<HostedAccount?> get accountChanges async* {
    yield currentAccount;
    yield* changes.stream;
  }

  @override
  Future<AccountResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async => const AccountResult(needsVerification: true);
  @override
  Future<AccountResult> signIn({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    if (failLogin) {
      throw const AccountFailure('Email or password is incorrect.');
    }
    return pendingLogin?.future ?? const AccountResult(needsVerification: true);
  }

  @override
  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    verificationCalls++;
    currentAccount = const HostedAccount(
      id: 'test-id',
      email: 'test@example.com',
      name: 'Test',
    );
    changes.add(currentAccount);
  }

  @override
  Future<void> resendVerification(String email) async {
    resendCalls++;
  }

  @override
  Future<void> signOut() async {
    currentAccount = null;
    changes.add(null);
  }
}

void main() {
  Future<void> mount(WidgetTester tester, FakeAccountService service) async {
    addTearDown(service.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostedAccountServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          routes: {
            '/':
                (_) => HostedAccountGate(
                  signedInBuilder:
                      (_) => const Scaffold(body: Text('Signed-in dashboard')),
                ),
            '/projects': (_) => const Scaffold(body: Text('Local dashboard')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillLogin(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('account-email')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password')),
      'password123',
    );
  }

  testWidgets(
    'missing cloud configuration disables sign-in but allows local hosting',
    (tester) async {
      await mount(tester, FakeAccountService(isConfigured: false));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Continue with local hosting'));
      await tester.tap(find.text('Continue with local hosting'));
      await tester.pumpAndSettle();
      expect(find.text('Local dashboard'), findsOneWidget);
    },
  );
  testWidgets('failed login displays feedback and permits retry', (
    tester,
  ) async {
    final service = FakeAccountService()..failLogin = true;
    await mount(tester, service);
    await fillLogin(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('signup leads to code verification and back returns to login', (
    tester,
  ) async {
    await mount(tester, FakeAccountService());
    await tester.tap(find.text('New to Buildify? Create an account'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('account-name')), 'Test');
    await fillLogin(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.byKey(const Key('account-code')), findsOneWidget);
    expect(find.text('Resend in 60s'), findsOneWidget);
    await tester.tap(find.text('Back to sign in'));
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byKey(const Key('account-name')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unconfirmed login permits resend and a valid code enters account session',
    (tester) async {
      final service = FakeAccountService();
      await mount(tester, service);
      await fillLogin(tester);
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.tap(find.text('Resend verification email'));
      await tester.pump();
      expect(service.resendCalls, 1);
      await tester.enterText(find.byKey(const Key('account-code')), '123456');
      await tester.tap(find.text('Verify email'));
      await tester.pumpAndSettle();
      expect(service.verificationCalls, 1);
      expect(find.text('Signed-in dashboard'), findsOneWidget);
    },
  );
  testWidgets('restored account opens the signed-in view', (tester) async {
    await mount(
      tester,
      FakeAccountService(
        currentAccount: const HostedAccount(
          id: 'test-id',
          email: 'test@example.com',
          name: 'Test',
        ),
      ),
    );
    expect(find.text('Signed-in dashboard'), findsOneWidget);
  });
  testWidgets('pending login prevents duplicate submission', (tester) async {
    final service =
        FakeAccountService()..pendingLogin = Completer<AccountResult>();
    await mount(tester, service);
    await fillLogin(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Please wait…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Please wait…'),
          )
          .onPressed,
      isNull,
    );
    expect(service.loginCalls, 1);
    service.pendingLogin!.complete(
      const AccountResult(needsVerification: true),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
