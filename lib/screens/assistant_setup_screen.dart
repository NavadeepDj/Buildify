import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../assistant/model_operations.dart';
import '../assistant/model_recommendation.dart';
import '../assistant/setup_controller.dart';
import '../assistant/cloud_intent.dart';
import '../models/ai_server_models.dart';
import '../providers/hosted_account_provider.dart';
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
  final request = TextEditingController();
  final List<IntentMessage> conversation = [];
  CloudIntent? intent;
  String? cloudMessage;
  bool interpreting = false;
  int generation = 0;

  @override
  void dispose() {
    generation++;
    request.dispose();
    super.dispose();
  }

  Future<void> sendRequest() async {
    final text = request.text.trim();
    if (text.isEmpty || interpreting) return;
    final service = ref.read(cloudIntentServiceProvider);
    if (service == null) {
      setState(
        () =>
            cloudMessage =
                'Cloud assistant is not configured in this build. Use the setup controls below.',
      );
      return;
    }
    final current = ++generation;
    // Failed turns are not added to history, so retry never creates two user turns.
    final messages = [...conversation, IntentMessage('user', text)];
    setState(() {
      interpreting = true;
      intent = null;
      cloudMessage = null;
    });
    try {
      final result = await service.interpret(messages);
      if (!mounted || current != generation) return;
      setState(() {
        conversation.addAll([
          IntentMessage('user', text),
          IntentMessage('assistant', result.reply),
        ]);
        intent = result;
        request.clear();
      });
    } catch (error) {
      if (!mounted || current != generation) return;
      setState(
        () =>
            cloudMessage =
                error is IntentFailure
                    ? error.message
                    : 'Cloud assistant unavailable. Use the setup controls below.',
      );
    } finally {
      if (mounted && current == generation) {
        setState(() => interpreting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(hostedAccountProvider, (previous, next) {
      if (previous?.asData?.value?.id != next.asData?.value?.id) {
        setState(() {
          generation++;
          conversation.clear();
          intent = null;
          interpreting = false;
          cloudMessage = null;
          request.clear();
        });
      }
    });
    final state = ref.watch(assistantSetupProvider);
    final controller = ref.read(assistantSetupProvider.notifier);
    final host = ref.watch(aiServerProvider);
    final plan = state.plan;
    final candidate = state.candidate;
    final completed = state.record?.state == ModelOperationState.succeeded;
    final connectionActive =
        completed &&
        host.status == ServerStatus.running &&
        host.selectedModelId == plan?.modelId &&
        ref.read(aiServerProvider.notifier).apiBaseUrl == state.endpoint;
    return Scaffold(
      appBar: AppBar(title: const Text('Model setup assistant')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'What would you like to run?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Describe your task. The assistant suggests settings, then this device checks resources and prepares a plan for your approval.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Your messages are sent to the cloud assistant. Avoid secrets. Model files and device paths are not sent. Conversation stays in this screen only.',
          ),
          for (final message in conversation)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${message.role == 'user' ? 'You' : 'Assistant'}: ${message.text}',
              ),
            ),
          TextField(
            controller: request,
            enabled: !state.busy && !interpreting,
            maxLength: 1500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Your request',
              hintText: 'Run a fast model for short answers on this laptop',
            ),
          ),
          FilledButton(
            onPressed:
                state.busy || interpreting || conversation.length >= 8
                    ? null
                    : sendRequest,
            child: Text(
              interpreting ? 'Understanding your request…' : 'Ask assistant',
            ),
          ),
          if (cloudMessage != null) Text(cloudMessage!),
          if (intent?.canPrepare == true)
            OutlinedButton(
              onPressed:
                  state.busy || interpreting
                      ? null
                      : () {
                        final suggestion = intent!;
                        setState(() {
                          task = suggestion.task;
                          preference = suggestion.preference;
                          intent = null;
                        });
                        controller.prepare(
                          task: task,
                          preference: preference,
                          stopExisting: stopExisting,
                        );
                      },
              child: Text(
                'Prepare suggested plan (${switch (intent!.task) {
                  'reasoning' => 'Reasoning',
                  'multilingual' => 'Multilingual answers',
                  _ => 'Short answers',
                }}, ${intent!.preference.name})',
              ),
            ),
          if (conversation.isNotEmpty)
            TextButton(
              onPressed:
                  state.busy || interpreting
                      ? null
                      : () => setState(() {
                        generation++;
                        conversation.clear();
                        intent = null;
                        cloudMessage = null;
                        request.clear();
                      }),
              child: const Text('Start a new conversation'),
            ),
          const SizedBox(height: 20),
          const Text('Setup controls'),
          DropdownButtonFormField<String>(
            key: ValueKey(task),
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
                    Text(
                      completed
                          ? 'Startup and a real inference request passed during this setup. Host must remain available.'
                          : 'Host must remain available. Startup compatibility is not yet verified.',
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
              connectionActive
                  ? 'Connection ready'
                  : 'Last verified connection (model is not currently active)',
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
              onPressed:
                  connectionActive
                      ? () => ref.read(aiServerProvider.notifier).stopServer()
                      : null,
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
