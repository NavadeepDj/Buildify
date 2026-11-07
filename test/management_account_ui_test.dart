import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildify_flutter/providers/hosted_account_provider.dart';
import 'package:buildify_flutter/providers/management_account_provider.dart';
import 'package:buildify_flutter/services/hosted_account_service.dart';
import 'package:buildify_flutter/services/management_account_service.dart';
import 'package:buildify_flutter/widgets/management_account_panel.dart';

import 'helpers/management_fixtures.dart'
    show config, FakeSessions, userA, userB;

class FakeManagementService extends ManagementAccountService {
  FakeManagementService(this.result)
    : super(config: config, sessions: FakeSessions());
  final Future<ManagementAccount> Function() result;
  int calls = 0;
  @override
  Future<ManagementAccount> fetchAccount() {
    calls++;
    return result();
  }
}

void main() {
  Widget panel({required List<Override> overrides, VoidCallback? signIn}) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          managementApiConfigProvider.overrideWithValue(config),
          ...overrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ManagementAccountPanel(
              fallbackName: 'Metadata fallback',
              onSignInAgain: signIn,
            ),
          ),
        ),
      );

  testWidgets(
    'loading shows no metadata fallback; success displays the server profile',
    (tester) async {
      final result = Completer<ManagementAccount?>();
      await tester.pumpWidget(
        panel(
          overrides: [
            managementAccountProvider.overrideWith((ref) => result.future),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('Loading your cloud profile…'), findsOneWidget);
      expect(find.text('Metadata fallback'), findsNothing);
      result.complete(
        const ManagementAccount(id: userA, displayName: 'Server profile'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server profile'), findsOneWidget);
    },
  );

  testWidgets(
    'rate-limit cooldown blocks retries and does not retry automatically',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        panel(
          overrides: [
            managementAccountProvider.overrideWith((ref) async {
              calls++;
              throw const ManagementFailure(
                ManagementFailureKind.rateLimited,
                retryAfterSeconds: 3,
              );
            }),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Retry in 3s'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Retry in 3s'))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Retry profile'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('Retry profile'));
      await tester.pump();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'expired sessions offer sign-in and raw exceptions never appear',
    (tester) async {
      var signIns = 0;
      await tester.pumpWidget(
        panel(
          signIn: () => signIns++,
          overrides: [
            managementAccountProvider.overrideWith(
              (ref) async =>
                  throw const ManagementFailure(
                    ManagementFailureKind.signInRequired,
                  ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in again'));
      expect(signIns, 1);
      await tester.pumpWidget(
        panel(
          overrides: [
            managementAccountProvider.overrideWith(
              (ref) async => throw Exception('private token value'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('private token'), findsNothing);
      expect(find.text('Retry profile'), findsOneWidget);
    },
  );

  test(
    'provider discards an old in-flight profile after account switching and signout',
    () async {
      final auth = StreamController<HostedAccount?>();
      final first = Completer<ManagementAccount>();
      final second = Completer<ManagementAccount>();
      late FakeManagementService service;
      service = FakeManagementService(
        () => service.calls == 1 ? first.future : second.future,
      );
      final container = ProviderContainer(
        overrides: [
          hostedAccountProvider.overrideWith((ref) => auth.stream),
          managementAccountServiceProvider.overrideWithValue(service),
        ],
      );
      final subscription = container.listen(
        managementAccountProvider,
        (_, _) {},
      );
      try {
        await container.read(managementAccountProvider.future);
        await Future<void>.delayed(Duration.zero);
        auth.add(
          const HostedAccount(id: userA, email: 'a@example.test', name: 'A'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(container.read(hostedAccountProvider).asData?.value?.id, userA);
        container.read(managementAccountProvider);
        expect(service.calls, 1);
        auth.add(
          const HostedAccount(id: userB, email: 'b@example.test', name: 'B'),
        );
        await Future<void>.delayed(Duration.zero);
        container.read(managementAccountProvider);
        expect(service.calls, 2);
        first.complete(
          const ManagementAccount(id: userA, displayName: 'Old account A'),
        );
        second.complete(
          const ManagementAccount(id: userB, displayName: 'Current account B'),
        );
        expect(
          (await container.read(managementAccountProvider.future))?.id,
          userB,
        );
        auth.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(await container.read(managementAccountProvider.future), isNull);
      } finally {
        subscription.close();
        container.dispose();
        await auth.close();
      }
    },
  );
}
