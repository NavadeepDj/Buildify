import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/assistant/model_recommendation.dart';
import 'package:buildify_flutter/assistant/setup_controller.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/screens/assistant_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends AiServerController {
  _Host(ModelProfile model) : super(initialize: false) {
    state = state.copyWith(models: [model]);
  }
}

class _Setup extends AssistantSetupController {
  _Setup(super.host);
  int approvals = 0;
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
}
