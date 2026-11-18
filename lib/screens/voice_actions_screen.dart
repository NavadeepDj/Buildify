import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../assistant/voice_tool_runtime.dart';
import 'assistant_setup_screen.dart';
import '../assistant/setup_controller.dart';
import '../assistant/model_recommendation.dart';
import '../assistant/status_probe_provider.dart';
import '../widgets/voice_review_widgets.dart';

class VoiceActionsScreen extends ConsumerWidget {
  const VoiceActionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(voiceActionsProvider);
    final busy = actions.any((a) => a.state == 'running');
    final setup = ref.watch(assistantSetupProvider);
    final runningRequest = ref.watch(voiceRunningModelRequestProvider);
    final email = ref.watch(voiceEndpointEmailProvider);
    final modelRequested =
        ref.watch(voiceSetupRequestsProvider) > 0 ||
        setup.plan != null ||
        setup.message != null ||
        runningRequest != null;
    final plan = setup.plan;
    final canApprove =
        plan != null &&
        setup.candidate != null &&
        !setup.busy &&
        setup.record == null &&
        DateTime.now().isBefore(plan.expiresAt);
    return Scaffold(
      appBar: AppBar(title: const Text('Voice action review')),
      body: VoiceReviewScrollView(
        children: [
          Text(
            'Review requests from your voice agent. Open a request to see its full details.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (email['state'] != 'not_requested')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceReviewHeading(
                      title: 'Endpoint email',
                      status: '${email['state']}',
                      icon: Icons.mail_outline,
                    ),
                    const SizedBox(height: 12),
                    if (email['summary'] != null) Text('${email['summary']}'),
                    if (email['recipient'] != null)
                      Text('To: ${email['recipient']}'),
                  ],
                ),
              ),
            ),
          if (runningRequest != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceReviewHeading(
                      title: 'Model setup request',
                      status: '${runningRequest['state']}',
                      icon: Icons.memory_outlined,
                    ),
                    const SizedBox(height: 12),
                    if (runningRequest['model'] != null)
                      Text('Model: ${runningRequest['model']}'),
                    Text('${runningRequest['summary']}'),
                    if (runningRequest['public_endpoint'] != null)
                      VoiceReviewLink(
                        value: '${runningRequest['public_endpoint']}',
                      ),
                  ],
                ),
              ),
            ),
          if (modelRequested && runningRequest == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceReviewHeading(
                      title: 'Model setup request',
                      status:
                          setup.busy
                              ? 'running'
                              : setup.record?.state.name ??
                                  (plan == null
                                      ? 'blocked'
                                      : canApprove
                                      ? 'needs_approval'
                                      : 'plan_expired'),
                      icon: Icons.memory_outlined,
                    ),
                    const SizedBox(height: 8),
                    if (setup.message != null) Text(setup.message!),
                    if (plan != null && setup.candidate != null) ...[
                      Text('Model: ${setup.candidate!.model.name}'),
                      Text(
                        'Download: ${(plan.downloadBytes / 1048576).toStringAsFixed(0)} MiB; existing files are checked before reuse.',
                      ),
                      Text(
                        'Memory budget: ${(setup.candidate!.estimatedMemoryBytes! / 1073741824).toStringAsFixed(2)} GiB plus host reserve. Context: ${plan.contextTokens} tokens.',
                      ),
                      Text(
                        ref.watch(voiceSetupRequestsProvider) > 0
                            ? 'After approval, Buildify publishes the model link and emails it to you.'
                            : 'Access stays on this device and its local network.',
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
                                : () => approveModelSetupFromOwnerUi(ref, plan),
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
                    settings: const RouteSettings(name: '/voice-setup'),
                    builder: (_) => const AssistantSetupScreen(),
                  ),
                ),
            child: const Text('Review model setup'),
          ),
          if (actions.isNotEmpty)
            Text(
              'Action history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (actions.isEmpty && !modelRequested)
            const Text('No voice requests yet.'),
          for (final action in actions.reversed)
            VoiceReviewActionCard(key: ValueKey(action.id), action: action),
        ],
      ),
    );
  }
}
