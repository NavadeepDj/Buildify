import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant/voice_actions.dart';
import '../assistant/voice_tool_runtime.dart';

class VoiceReviewScrollView extends StatefulWidget {
  const VoiceReviewScrollView({super.key, required this.children});
  final List<Widget> children;

  @override
  State<VoiceReviewScrollView> createState() => _VoiceReviewScrollViewState();
}

class _VoiceReviewScrollViewState extends State<VoiceReviewScrollView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(double destination) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      destination.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.pageDown): () {
            if (_scroll.hasClients) {
              _move(_scroll.offset + _scroll.position.viewportDimension * .8);
            }
          },
          const SingleActivator(LogicalKeyboardKey.pageUp): () {
            if (_scroll.hasClients) {
              _move(_scroll.offset - _scroll.position.viewportDimension * .8);
            }
          },
          const SingleActivator(LogicalKeyboardKey.home): () => _move(0),
          const SingleActivator(LogicalKeyboardKey.end): () {
            if (_scroll.hasClients) _move(_scroll.position.maxScrollExtent);
          },
        },
        child: Focus(
          autofocus: true,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              interactive: true,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final side = math.max(20.0, (bounds.maxWidth - 920) / 2);
                  return ListView.separated(
                    controller: _scroll,
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(side, 24, side, 180),
                    itemCount: widget.children.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (_, index) => widget.children[index],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String voiceReviewStatusLabel(String state) => switch (state) {
  'needs_approval' => 'Needs approval',
  'not_configured' => 'Setup needed',
  'waiting_for_model' => 'Waiting for model',
  'waiting_for_endpoint' => 'Preparing link',
  'already_running' => 'Already running',
  'succeeded' => 'Completed',
  'verifyingArtifact' => 'Checking model',
  'verifyingInference' => 'Checking response',
  'plan_expired' => 'Plan expired',
  'no_compatible_plan' => 'Needs attention',
  _ => state
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
};

class VoiceReviewHeading extends StatelessWidget {
  const VoiceReviewHeading({
    super.key,
    required this.title,
    required this.status,
    this.icon = Icons.record_voice_over_outlined,
  });
  final String title, status;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attention = {
      'failed',
      'needsReview',
      'blocked',
      'not_configured',
    }.contains(status);
    final color =
        attention
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        border: Border.all(color: color.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        voiceReviewStatusLabel(status),
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 10), badge],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            Flexible(child: badge),
          ],
        );
      },
    );
  }
}

class VoiceReviewLink extends StatelessWidget {
  const VoiceReviewLink({super.key, required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    final link = value.replaceFirst(RegExp(r'/v1/?$'), '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            link,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'Copy model link',
          icon: const Icon(Icons.copy_outlined, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Model link copied')),
              );
            }
          },
        ),
      ],
    );
  }
}

String _actionTitle(String tool) => switch (tool) {
  'stop_model' => 'Stop model',
  'share_model' => 'Share model endpoint',
  'select_model' => 'Select model',
  'download_model' => 'Download model',
  'delete_model' => 'Delete model',
  'start_project' => 'Start project',
  'restart_project' => 'Restart project',
  'delete_project' => 'Delete project',
  _ => voiceReviewStatusLabel(tool),
};

String? _actionRisk(String tool) => switch (tool) {
  'delete_project' => 'Deletes this project and may remove its files.',
  'delete_model' => 'Deletes this model’s files from this device.',
  'start_project' || 'restart_project' =>
    'Runs saved project scripts and may publish its configured route.',
  'stop_model' => 'Stops the current model and makes its endpoint unavailable.',
  'share_model' =>
    'Makes the running model reachable through its public route.',
  _ => null,
};

class VoiceReviewActionCard extends ConsumerWidget {
  const VoiceReviewActionCard({super.key, required this.action});
  final VoiceAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref
        .watch(voiceActionsProvider)
        .any((a) => a.state == 'running');
    final target =
        (action.localReview ?? '')
            .split('\n')
            .where((s) => s.startsWith('Model: ') || s.startsWith('Project: '))
            .firstOrNull;
    final risk = _actionRisk(action.tool);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VoiceReviewHeading(
              title: _actionTitle(action.tool),
              status: action.state,
              icon:
                  action.tool.startsWith('delete')
                      ? Icons.delete_outline
                      : Icons.task_alt_outlined,
            ),
            const SizedBox(height: 12),
            if (target != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(target),
              ),
            Text(
              action.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (risk != null && action.state == 'needs_approval') ...[
              const SizedBox(height: 10),
              Text(
                risk,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (action.result?['summary'] case final String summary) ...[
              const SizedBox(height: 10),
              Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDetails(context),
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: const Text('View details'),
                ),
                if (action.state == 'needs_approval') ...[
                  FilledButton(
                    onPressed:
                        busy
                            ? null
                            : () => ref
                                .read(voiceActionsProvider.notifier)
                                .approve(action.id),
                    child: const Text('Approve this action'),
                  ),
                  TextButton(
                    onPressed:
                        () => ref
                            .read(voiceActionsProvider.notifier)
                            .reject(action.id),
                    child: const Text('Reject'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder:
            (_) => FractionallySizedBox(
              heightFactor: .88,
              child: _VoiceActionDetails(action: action),
            ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder:
            (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 700,
                height: math.min(760, MediaQuery.sizeOf(context).height * .86),
                child: _VoiceActionDetails(action: action),
              ),
            ),
      );
    }
  }
}

class _VoiceActionDetails extends ConsumerStatefulWidget {
  const _VoiceActionDetails({required this.action});
  final VoiceAction action;
  @override
  ConsumerState<_VoiceActionDetails> createState() =>
      _VoiceActionDetailsState();
}

class _VoiceActionDetailsState extends ConsumerState<_VoiceActionDetails> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.watch(voiceActionsProvider);
    final action =
        actions.where((a) => a.id == widget.action.id).firstOrNull ??
        widget.action;
    final busy = actions.any((a) => a.state == 'running');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: VoiceReviewHeading(
                  title: _actionTitle(action.tool),
                  status: action.state,
                ),
              ),
              IconButton(
                tooltip: 'Close review',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request details',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(action.localReview ?? action.description),
                    const SizedBox(height: 20),
                    Text(
                      'Requested ${TimeOfDay.fromDateTime(action.createdAt.toLocal()).format(context)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_actionRisk(action.tool) case final String risk) ...[
                      const SizedBox(height: 16),
                      Text(
                        risk,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (action.result != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Result',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${action.result!['summary'] ?? action.result!['error'] ?? voiceReviewStatusLabel(action.state)}',
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Technical details'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(action.result),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (action.state == 'needs_approval') ...[
                  OutlinedButton(
                    onPressed:
                        () => ref
                            .read(voiceActionsProvider.notifier)
                            .reject(action.id),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed:
                        busy
                            ? null
                            : () => ref
                                .read(voiceActionsProvider.notifier)
                                .approve(action.id),
                    child: const Text('Approve this action'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
