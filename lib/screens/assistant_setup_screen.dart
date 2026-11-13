import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../assistant/model_operations.dart';
import '../assistant/model_recommendation.dart';
import '../assistant/setup_controller.dart';
import '../providers/ai_server_provider.dart';

class AssistantSetupScreen extends ConsumerStatefulWidget {
  const AssistantSetupScreen({super.key});
  @override
  ConsumerState<AssistantSetupScreen> createState() =>
      _AssistantSetupScreenState();
}

class _AssistantSetupScreenState extends ConsumerState<AssistantSetupScreen> {
  ModelPreference preference = ModelPreference.balanced;
  String task = 'short_answers';
  bool stopExisting = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantSetupProvider);
    final controller = ref.read(assistantSetupProvider.notifier);
    final host = ref.watch(aiServerProvider);
    final plan = state.plan;
    final candidate = state.candidate;
    final completed = state.record?.state == ModelOperationState.succeeded;
    return Scaffold(
      appBar: AppBar(title: const Text('Model setup assistant')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose what you need',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'This guided setup checks resources, prepares a plan and tests the model. Cloud conversation will be available when its service is configured.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: task,
            decoration: const InputDecoration(labelText: 'Task'),
            items: const [
              DropdownMenuItem(
                value: 'short_answers',
                child: Text('Short answers'),
              ),
              DropdownMenuItem(
                value: 'multilingual',
                child: Text('Multilingual answers'),
              ),
              DropdownMenuItem(value: 'reasoning', child: Text('Reasoning')),
            ],
            onChanged: state.busy ? null : (v) => setState(() => task = v!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ModelPreference>(
            segments: const [
              ButtonSegment(value: ModelPreference.speed, label: Text('Speed')),
              ButtonSegment(
                value: ModelPreference.balanced,
                label: Text('Balanced'),
              ),
              ButtonSegment(
                value: ModelPreference.quality,
                label: Text('Quality'),
              ),
            ],
            selected: {preference},
            onSelectionChanged:
                state.busy
                    ? null
                    : (v) => setState(() => preference = v.single),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: stopExisting,
            title: const Text('Allow replacing the current model session'),
            subtitle: const Text(
              'The current session may stop if you approve this plan.',
            ),
            onChanged:
                state.busy
                    ? null
                    : (v) => setState(() => stopExisting = v ?? false),
          ),
          FilledButton(
            onPressed:
                state.busy || host.models.isEmpty
                    ? null
                    : () => controller.prepare(
                      preference: preference,
                      task: task,
                      stopExisting: stopExisting,
                    ),
            child: const Text('Prepare a plan'),
          ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(state.message!),
            ),
          if (plan != null && candidate != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.model.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Download: ${(plan.downloadBytes / 1048576).toStringAsFixed(0)} MiB; an existing file is verified before reuse.',
                    ),
                    Text(
                      'Memory budget: ${(candidate.model.requirements!.estimatedMemoryBytes / 1073741824).toStringAsFixed(1)} GiB, plus host reserve.',
                    ),
                    Text('Context: ${plan.contextTokens} tokens.'),
                    const Text(
                      'Access: this device / reachable local network. No public tunnel will be started.',
                    ),
                    Text(
                      plan.stopExisting
                          ? 'Current model may be stopped.'
                          : 'An active model will block setup.',
                    ),
                    const Text(
                      'Host must remain available. Startup compatibility is not yet verified.',
                    ),
                    const SizedBox(height: 14),
                    if (!state.busy && !completed)
                      FilledButton(
                        onPressed:
                            state.record == null
                                ? controller.approveAndRun
                                : null,
                        child: const Text('Approve and run'),
                      ),
                  ],
                ),
              ),
            ),
          if (state.busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(_stage(state.record?.state)),
            ),
            OutlinedButton(
              onPressed: controller.cancel,
              child: const Text('Cancel setup'),
            ),
          ],
          if (completed && state.endpoint != null) ...[
            const SizedBox(height: 18),
            Text(
              'Connection ready',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SelectableText('${state.endpoint}/v1'),
            Text('Model: ${plan!.modelId}'),
            Text(
              'Test request: ${state.inferenceDuration?.inMilliseconds ?? 0} ms. This is one test, not a benchmark.',
            ),
            Text(
              host.security.requireApiKey
                  ? 'Use the API key configured in Security & Safety.'
                  : 'This local endpoint currently has no API-key requirement.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  () => Clipboard.setData(
                    ClipboardData(text: '${state.endpoint}/v1'),
                  ),
              icon: const Icon(Icons.copy),
              label: const Text('Copy base URL'),
            ),
            OutlinedButton(
              onPressed: () => ref.read(aiServerProvider.notifier).stopServer(),
              child: const Text('Stop model'),
            ),
          ],
        ],
      ),
    );
  }

  String _stage(ModelOperationState? state) => switch (state) {
    ModelOperationState.preparing => 'Checking current settings',
    ModelOperationState.downloading => 'Downloading or reusing the model',
    ModelOperationState.verifyingArtifact => 'Checking model integrity',
    ModelOperationState.configuring => 'Applying the approved settings',
    ModelOperationState.starting => 'Starting the model',
    ModelOperationState.verifyingInference => 'Testing a real response',
    _ => 'Preparing setup',
  };
}
