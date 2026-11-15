import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../assistant/voice_tool_runtime.dart';
import 'assistant_setup_screen.dart';
import '../assistant/setup_controller.dart';
import '../assistant/model_recommendation.dart';
import '../assistant/status_probe_provider.dart';

class VoiceActionsScreen extends ConsumerWidget {
  const VoiceActionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(voiceActionsProvider);
    final busy = actions.any((a) => a.state == 'running');
    final setup = ref.watch(assistantSetupProvider);
    final modelRequested =
        ref.watch(voiceSetupRequestsProvider) > 0 ||
        setup.plan != null ||
        setup.message != null;
    final plan = setup.plan;
    final canApprove =
        plan != null &&
        setup.candidate != null &&
        !setup.busy &&
        setup.record == null &&
        DateTime.now().isBefore(plan.expiresAt);
    return Scaffold(
      appBar: AppBar(title: const Text('Voice action review')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (modelRequested)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Model setup request',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      setup.busy
                          ? 'Status: preparing or running'
                          : plan == null
                          ? 'Status: blocked — nothing to approve'
                          : setup.record != null
                          ? 'Status: ${setup.record!.state.name}'
                          : canApprove
                          ? 'Status: approval required'
                          : 'Status: plan expired — prepare a new plan',
                    ),
                    if (setup.message != null) Text(setup.message!),
                    if (plan != null && setup.candidate != null) ...[
                      Text('Model: ${setup.candidate!.model.name}'),
                      Text(
                        'Download: ${(plan.downloadBytes / 1048576).toStringAsFixed(0)} MiB; existing files are checked before reuse.',
                      ),
                      Text(
                        'Memory budget: ${(setup.candidate!.model.requirements!.estimatedMemoryBytes / 1073741824).toStringAsFixed(2)} GiB plus host reserve. Context: ${plan.contextTokens} tokens.',
                      ),
                      const Text(
                        'Device/LAN access only. No public tunnel will be started.',
                      ),
                      Text(
                        plan.stopExisting
                            ? 'May stop the current model.'
                            : 'An active model will block setup.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (canApprove)
                      FilledButton(
                        onPressed:
                            busy
                                ? null
                                : () =>
                                    ref
                                        .read(assistantSetupProvider.notifier)
                                        .approveAndRun(),
                        child: const Text('Approve and run model'),
                      ),
                    if (!setup.busy &&
                        (plan == null || setup.record != null || !canApprove))
                      OutlinedButton(
                        onPressed:
                            () => ref
                                .read(assistantSetupProvider.notifier)
                                .prepare(
                                  preference: ModelPreference.speed,
                                  modelId: plan?.modelId,
                                ),
                        child: const Text('Retry model setup checks'),
                      ),
                    if (setup.busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
          OutlinedButton(
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AssistantSetupScreen(),
                  ),
                ),
            child: const Text('Review model setup'),
          ),
          const Text(
            'Requests from your paired voice agent. Review each action before it changes this device. Starting a project can run its saved scripts, stop another project, and publish its configured route. Deleting an ephemeral project can remove its files.',
          ),
          const SizedBox(height: 16),
          if (actions.isEmpty && !modelRequested)
            const Text('No voice requests yet.'),
          for (final action in actions.reversed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.tool.replaceAll('_', ' '),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(action.localReview ?? action.description),
                    const SizedBox(height: 8),
                    Text('Status: ${action.state}'),
                    if (action.result != null) Text(action.result.toString()),
                    if (action.state == 'needs_approval')
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed:
                                busy
                                    ? null
                                    : () => ref
                                        .read(voiceActionsProvider.notifier)
                                        .approve(action.id),
                            child: const Text('Approve this action'),
                          ),
                          OutlinedButton(
                            onPressed:
                                () => ref
                                    .read(voiceActionsProvider.notifier)
                                    .reject(action.id),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
