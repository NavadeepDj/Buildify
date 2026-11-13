import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/assistant/model_recommendation.dart';
import 'package:buildify_flutter/assistant/setup_controller.dart';
import 'package:buildify_flutter/assistant/cloud_intent.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/assistant_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/management_fixtures.dart';

class _Cloud extends CloudIntentService {
  _Cloud() : super(config, FakeSessions());
  @override
  Future<CloudIntent> interpret(List<IntentMessage> messages) async =>
      CloudIntent.parse({
        'status': 'ready',
        'task': 'short_answers',
        'preference': 'speed',
        'scope': 'device_network',
        'reply': 'I can prepare a fast local setup plan.',
      });
}

class _Host extends AiServerController {
  _Host(ModelProfile model) : super(initialize: false) {
    state = state.copyWith(models: [model], selectedModelId: model.id);
  }
  void running(bool value) =>
      state = state.copyWith(
        status: value ? ServerStatus.running : ServerStatus.stopped,
      );
}

class _Setup extends AssistantSetupController {
  _Setup(super.host);
  int approvals = 0;
  void complete() {
    final plan = state.plan!;
    state = AssistantSetupState(
      plan: plan,
      candidate: state.candidate,
      record: ModelOperationRecord(
        id: plan.id,
        planDigest: plan.digest,
        state: ModelOperationState.succeeded,
        updatedAt: DateTime.now(),
      ),
      endpoint: host.apiBaseUrl,
      inferenceDuration: const Duration(milliseconds: 888),
    );
  }

  @override
  Future<void> prepare({
    ModelPreference preference = ModelPreference.balanced,
    String task = 'short_answers',
    bool stopExisting = false,
  }) async {
    final model = host.snapshot.models.first;
    final r = model.requirements!;
    final now = DateTime.now();
    state = AssistantSetupState(
      plan: ModelOperationPlan(
        id: 'test-plan',
        modelId: model.id,
        artifactSha256: r.sha256,
        downloadBytes: r.bytes,
        scope: ModelAccessScope.deviceNetwork,
        stopExisting: stopExisting,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      candidate: ModelCandidate(
        model: model,
        reuseInstalled: false,
        blockers: ['runtime_verification_required'],
      ),
    );
  }

  @override
  Future<void> approveAndRun() async {
    approvals++;
    state = AssistantSetupState(
      busy: true,
      plan: state.plan,
      candidate: state.candidate,
    );
  }
}

void main() {
  testWidgets('verified inference becomes historical when stopped', (
    tester,
  ) async {
    final raw =
        (jsonDecode(File('assets/models/catalog.json').readAsStringSync())
                as Map)['models']
            as List;
    final host = _Host(
      ModelProfile.fromJson(raw.first as Map<String, dynamic>),
    );
    final setup = _Setup(host);
    await setup.prepare();
    setup.complete();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiServerProvider.overrideWith((ref) => host),
          assistantSetupProvider.overrideWith((ref) => setup),
        ],
        child: const MaterialApp(home: AssistantSetupScreen()),
      ),
    );
    final scrollable =
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
    await tester.scrollUntilVisible(
      find.textContaining('Last verified connection'),
      250,
      scrollable: scrollable,
    );
    expect(
      find.textContaining('Startup and a real inference request passed'),
      findsOneWidget,
    );
    expect(find.textContaining('not yet verified'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Stop model'),
      100,
      scrollable: scrollable,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Stop model'),
          )
          .onPressed,
      isNull,
    );
    host.running(true);
    await tester.pump();
    expect(find.text('Connection ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('shows review before execution and disables duplicate approval', (
    tester,
  ) async {
    final raw =
        (jsonDecode(File('assets/models/catalog.json').readAsStringSync())
                as Map)['models']
            as List;
    final host = _Host(
      ModelProfile.fromJson(raw.first as Map<String, dynamic>),
    );
    final setup = _Setup(host);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiServerProvider.overrideWith((ref) => host),
          assistantSetupProvider.overrideWith((ref) => setup),
        ],
        child: const MaterialApp(home: AssistantSetupScreen()),
      ),
    );
    expect(find.text('Approve and run'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Prepare a plan'),
      250,
      scrollable:
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.tap(find.text('Prepare a plan'));
    await tester.pumpAndSettle();
    expect(find.text('Approve and run'), findsOneWidget);
    expect(find.textContaining('No public tunnel'), findsOneWidget);
    expect(find.textContaining('not yet verified'), findsOneWidget);
    await tester.ensureVisible(find.text('Approve and run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and run'));
    await tester.pump();
    expect(setup.approvals, 1);
    expect(find.text('Cancel setup'), findsOneWidget);
    expect(find.text('Approve and run'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cloud suggestion prepares a review without approving execution',
    (tester) async {
      final raw =
          (jsonDecode(File('assets/models/catalog.json').readAsStringSync())
                  as Map)['models']
              as List;
      final host = _Host(
        ModelProfile.fromJson(raw.first as Map<String, dynamic>),
      );
      final setup = _Setup(host);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiServerProvider.overrideWith((ref) => host),
            assistantSetupProvider.overrideWith((ref) => setup),
            cloudIntentServiceProvider.overrideWithValue(_Cloud()),
          ],
          child: const MaterialApp(home: AssistantSetupScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Fast local answers');
      await tester.tap(find.text('Ask assistant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Assistant: I can prepare'), findsOneWidget);
      expect(setup.state.plan, isNull);
      final suggested = find.textContaining('Prepare suggested plan');
      await tester.ensureVisible(suggested);
      await tester.tap(suggested);
      await tester.pumpAndSettle();
      expect(setup.state.plan, isNotNull);
      expect(setup.approvals, 0);
      expect(setup.state.plan!.scope, ModelAccessScope.deviceNetwork);
      expect(setup.state.plan!.stopExisting, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
