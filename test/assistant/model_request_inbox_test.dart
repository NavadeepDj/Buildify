import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/assistant/setup_controller.dart';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/assistant/model_recommendation.dart';
import 'package:buildify_flutter/assistant/status_probe_provider.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/voice_actions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends AiServerController {
  _Host() : super(initialize: false);
}

class _Setup extends AssistantSetupController {
  _Setup(super.host, AssistantSetupState initial) {
    state = initial;
  }
  int approvals = 0;
  @override
  Future<void> approveAndRun() async {
    approvals++;
  }
}

void main() {
  testWidgets(
    'blocked model request remains visible and counted with no approval button',
    (tester) async {
      final host = _Host();
      final setup = _Setup(
        host,
        const AssistantSetupState(
          failureCode: 'insufficient_memory',
          message:
              'Not enough available memory: 2.0 GiB available; 2.6 GiB required. No model is waiting for approval.',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          assistantSetupProvider.overrideWith((ref) => setup),
          voiceSetupRequestsProvider.overrideWith((ref) => 1),
        ],
      );
      addTearDown(() {
        container.dispose();
        host.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: VoiceActionsScreen()),
        ),
      );
      expect(find.text('Model setup request'), findsOneWidget);
      expect(find.textContaining('2.0 GiB available'), findsOneWidget);
      expect(find.text('No voice requests yet.'), findsNothing);
      expect(find.text('Approve and run model'), findsNothing);
      expect(container.read(pendingVoiceRequestsProvider), 1);
    },
  );
  testWidgets('real model plan is reviewed and approved from the same inbox', (
    tester,
  ) async {
    final catalog =
        jsonDecode(File('assets/models/catalog.json').readAsStringSync())
            as Map;
    final model = ModelProfile.fromJson(
      (catalog['models'] as List).first as Map<String, dynamic>,
    );
    final now = DateTime.now();
    final host = _Host();
    final setup = _Setup(
      host,
      AssistantSetupState(
        plan: ModelOperationPlan(
          id: 'inbox-fixture',
          modelId: model.id,
          artifactSha256: model.requirements!.sha256,
          downloadBytes: model.requirements!.bytes,
          scope: ModelAccessScope.deviceNetwork,
          stopExisting: false,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        candidate: ModelCandidate(
          model: model,
          reuseInstalled: true,
          blockers: const [],
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        assistantSetupProvider.overrideWith((ref) => setup),
        voiceSetupRequestsProvider.overrideWith((ref) => 1),
      ],
    );
    addTearDown(() {
      container.dispose();
      host.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: VoiceActionsScreen()),
      ),
    );
    expect(find.text('Model: ${model.name}'), findsOneWidget);
    expect(container.read(pendingVoiceRequestsProvider), 1);
    await tester.ensureVisible(find.text('Approve and run model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and run model'));
    expect(setup.approvals, 1);
    expect(tester.takeException(), isNull);
  });
}
