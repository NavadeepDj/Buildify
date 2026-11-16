import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/embedded_backend.dart';
import '../providers/ai_server_provider.dart';

class EnvManagementPage extends ConsumerStatefulWidget {
  const EnvManagementPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<EnvManagementPage> createState() => _EnvManagementPageState();
}

class _EnvManagementPageState extends ConsumerState<EnvManagementPage> {
  static const int _collapsedCount = 9;
  static final RegExp _keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  final List<_EnvDraftEntry> _draft = [];
  final Set<String> _revealedKeys = {};

  bool _editing = false;
  bool _saving = false;
  bool _busy = false;
  bool _expanded = false;

  @override
  void dispose() {
    _disposeDraft();
    super.dispose();
  }

  void _disposeDraft() {
    for (final entry in _draft) {
      entry.dispose();
    }
    _draft.clear();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _EnvPalette.elevated,
        content: Text(
          message,
          style: GoogleFonts.spaceMono(fontSize: 12, color: _EnvPalette.text),
        ),
      ),
    );
  }

  void _startEditing(Map<String, String> envVars, {bool addBlank = false}) {
    _disposeDraft();
    final entries =
        envVars.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      _draft.add(_EnvDraftEntry(key: entry.key, value: entry.value));
    }
    if (addBlank || _draft.isEmpty) {
      _draft.add(_EnvDraftEntry());
    }
    setState(() {
      _editing = true;
      _expanded = true;
    });
    if (addBlank || entries.isEmpty) {
      _focusLastDraft();
    }
  }

  void _focusLastDraft() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _draft.isEmpty) return;
      _draft.last.keyFocusNode.requestFocus();
    });
  }

  void _addRow() {
    setState(() => _draft.add(_EnvDraftEntry()));
    _focusLastDraft();
  }

  void _removeRow(int index) {
    if (index < 0 || index >= _draft.length) return;
    _draft.removeAt(index).dispose();
    setState(() {});
  }

  void _cancelEditing() {
    _disposeDraft();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    final envVars = <String, String>{};
    final seenKeys = <String>{};
    var hasError = false;

    for (final entry in _draft) {
      entry.keyError = null;
      final key = entry.keyController.text.trim();
      final value = entry.valueController.text;
      if (key.isEmpty) {
        entry.keyError = 'Key is required';
        hasError = true;
        continue;
      }
      if (!_keyPattern.hasMatch(key)) {
        entry.keyError = 'Use letters, numbers and _';
        hasError = true;
        continue;
      }
      if (!seenKeys.add(key)) {
        entry.keyError = 'Key already exists';
        hasError = true;
        continue;
      }
      envVars[key] = value;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(embeddedBackendProvider)
          .updateEnvVars(widget.projectId, envVars);
      if (!mounted) return;
      _disposeDraft();
      _revealedKeys.clear();
      setState(() {
        _saving = false;
        _editing = false;
      });
      _showMessage('Environment variables saved');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Could not save variables: $error');
    }
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showMessage(message);
  }

  Future<void> _export(Map<String, String> envVars) async {
    if (envVars.isEmpty) {
      _showMessage('No variables to export');
      return;
    }
    final entries =
        envVars.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final content = entries.map((e) => '${e.key}=${e.value}').join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    _showMessage('${envVars.length} variables copied as .env');
  }

  Future<void> _toggleServer(BackendProject project, BackendState state) async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = ref.read(embeddedBackendProvider);
    try {
      if (project.isLive) {
        final session = state.activeSession;
        if (session != null && session.projectId == project.id) {
          await service.stopSession(sessionId: session.id);
          if (mounted) _showMessage('Server stopped');
        }
      } else {
        await service.startSession(projectId: project.id);
        if (mounted) _showMessage('Server started');
      }
    } catch (error) {
      if (mounted) _showMessage('Action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _endpointFor(BackendProject project, BackendState state) {
    if (project.liveUrl.isNotEmpty) return project.liveUrl;
    final session = state.activeSession;
    if (session != null && session.projectId == project.id) {
      return session.publicUrl;
    }
    return 'localhost:${project.port}';
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(embeddedBackendProvider);
    final state = ref.watch(backendStateProvider).value ?? service.state;
    final matches = state.projects.where((p) => p.id == widget.projectId);
    final project = matches.isEmpty ? null : matches.first;

    final entries =
        project == null
            ? const <MapEntry<String, String>>[]
            : (project.envVars.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)));
    final visibleEntries =
        _expanded ? entries : entries.take(_collapsedCount).toList();

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _EnvPalette.background,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _EnvPalette.text,
          selectionColor: _EnvPalette.selection,
          selectionHandleColor: _EnvPalette.text,
        ),
      ),
      child: Scaffold(
        backgroundColor: _EnvPalette.background,
        body: Column(
          children: [
            _TopBar(
              onBack: () => Navigator.of(context).maybePop(),
              onSettings:
                  () => _showMessage(
                    'Variables are injected into the server at start.',
                  ),
            ),
            Expanded(
              child:
                  project == null
                      ? const _MissingProject()
                      : ListView(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 32,
                        ),
                        children: [
                          _ServiceContextHeader(
                            project: project,
                            busy: _busy,
                            onToggleServer: () => _toggleServer(project, state),
                            onConnect:
                                () => _copy(
                                  _endpointFor(project, state),
                                  'Endpoint copied',
                                ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader(
                                  editing: _editing,
                                  onAdd: () {
                                    if (_editing) {
                                      _addRow();
                                    } else {
                                      _startEditing(
                                        project.envVars,
                                        addBlank: true,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 8),
                                const _SectionDescription(),
                                const SizedBox(height: 12),
                                _VariablesCard(
                                  count:
                                      _editing ? _draft.length : entries.length,
                                  editing: _editing,
                                  saving: _saving,
                                  onCancel: _saving ? null : _cancelEditing,
                                  onSave: _saving ? null : _save,
                                  onEdit: () => _startEditing(project.envVars),
                                  onExport:
                                      entries.isEmpty
                                          ? null
                                          : () => _export(project.envVars),
                                  onToggleExpanded:
                                      entries.length > _collapsedCount
                                          ? () => setState(
                                            () => _expanded = !_expanded,
                                          )
                                          : null,
                                  expanded: _expanded,
                                  hasMore: entries.length > _collapsedCount,
                                  emptyState:
                                      entries.isEmpty && !_editing
                                          ? _EmptyVariables(
                                            onAdd:
                                                () => _startEditing(
                                                  project.envVars,
                                                  addBlank: true,
                                                ),
                                          )
                                          : null,
                                  children: [
                                    if (_editing)
                                      ..._buildDraftRows()
                                    else
                                      ..._buildViewRows(visibleEntries),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDraftRows() {
    final rows = <Widget>[];
    for (var i = 0; i < _draft.length; i++) {
      if (i > 0) {
        rows.add(const _CardDivider());
      }
      rows.add(_EnvEditRow(entry: _draft[i], onRemove: () => _removeRow(i)));
    }
    return rows;
  }

  List<Widget> _buildViewRows(List<MapEntry<String, String>> entries) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) {
        rows.add(const _CardDivider());
      }
      final entry = entries[i];
      rows.add(
        _EnvViewRow(
          envKey: entry.key,
          value: entry.value,
          revealed: _revealedKeys.contains(entry.key),
          onCopyKey: () => _copy(entry.key, 'Key copied'),
          onToggleReveal: () {
            setState(() {
              if (!_revealedKeys.add(entry.key)) {
                _revealedKeys.remove(entry.key);
              }
            });
          },
        ),
      );
    }
    return rows;
  }
}

// ==========================================
// TOP BAR
// ==========================================
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onSettings,
  });

  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(4, top + 6, 16, 8),
      decoration: BoxDecoration(
        color: _EnvPalette.background.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(color: _EnvPalette.border.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left),
            iconSize: 24,
            color: _EnvPalette.muted,
            tooltip: 'Go back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          const SizedBox(width: 4),
          const _BuildifyMark(size: 22),
          const SizedBox(width: 8),
          Text(
            'buildify',
            style: GoogleFonts.spaceMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: _EnvPalette.text,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            iconSize: 19,
            color: _EnvPalette.muted,
            tooltip: 'Environment info',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SERVICE CONTEXT HEADER
// ==========================================
class _ServiceContextHeader extends StatelessWidget {
  const _ServiceContextHeader({
    required this.project,
    required this.busy,
    required this.onToggleServer,
    required this.onConnect,
  });

  final BackendProject project;
  final bool busy;
  final VoidCallback onToggleServer;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final isLive = project.isLive;
    final providerBadge = _providerLabel(project.repoProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: _EnvPalette.serviceHeader,
        border: Border(bottom: BorderSide(color: _EnvPalette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 14,
                color: _EnvPalette.muted,
              ),
              const SizedBox(width: 6),
              Text('>', style: _breadcrumbStyle),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _breadcrumbStyle,
                ),
              ),
              const SizedBox(width: 6),
              Text('>', style: _breadcrumbStyle),
              const SizedBox(width: 6),
              Text(
                'environment',
                style: _breadcrumbStyle.copyWith(
                  color: _EnvPalette.softText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.public, size: 14, color: _EnvPalette.muted),
              const SizedBox(width: 6),
              Text(
                'WEB SERVICE',
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _EnvPalette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      project.name,
                      style: GoogleFonts.spaceMono(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: _EnvPalette.text,
                      ),
                    ),
                    _MetaBadge(providerBadge),
                    const _MetaBadge('Free', purple: true),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(live: isLive),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HeaderButton(
                  label:
                      busy
                          ? 'Working…'
                          : (isLive ? 'Stop Server' : 'Manual Deploy'),
                  icon: Icons.bolt,
                  primary: true,
                  onTap: busy ? null : onToggleServer,
                ),
              ),
              const SizedBox(width: 8),
              _HeaderButton(
                label: 'Connect',
                trailing: Icons.expand_more,
                onTap: onConnect,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MAIN SECTION
// ==========================================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.editing, required this.onAdd});

  final bool editing;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Environment Variables',
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: _EnvPalette.text,
            ),
          ),
        ),
        _SmallButton(icon: Icons.add, label: 'Add Group', onTap: onAdd),
      ],
    );
  }
}

class _SectionDescription extends StatelessWidget {
  const _SectionDescription();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        Text(
          'Set environment-specific config and secrets (such as API keys), '
          'then read those values from your code. ',
          style: _bodyStyle,
        ),
        Text(
          'Learn more.',
          style: _bodyStyle.copyWith(
            color: _EnvPalette.softText,
            decoration: TextDecoration.underline,
            decorationColor: _EnvPalette.softText,
          ),
        ),
      ],
    );
  }
}

class _VariablesCard extends StatelessWidget {
  const _VariablesCard({
    required this.count,
    required this.editing,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.onEdit,
    required this.onExport,
    required this.onToggleExpanded,
    required this.expanded,
    required this.hasMore,
    required this.emptyState,
    required this.children,
  });

  final int count;
  final bool editing;
  final bool saving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final VoidCallback onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onToggleExpanded;
  final bool expanded;
  final bool hasMore;
  final Widget? emptyState;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final label =
        count == 1 ? '1 VARIABLE CONFIGURED' : '$count VARIABLES CONFIGURED';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _EnvPalette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _EnvPalette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: _EnvPalette.elevated,
              border: Border(bottom: BorderSide(color: _EnvPalette.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _EnvPalette.muted,
                    ),
                  ),
                ),
                if (editing) ...[
                  _SmallButton(label: 'Cancel', onTap: onCancel),
                  const SizedBox(width: 8),
                  _SmallButton(
                    icon: saving ? null : Icons.check,
                    label: saving ? 'Saving…' : 'Save',
                    primary: true,
                    onTap: onSave,
                  ),
                ] else ...[
                  _SmallButton(
                    icon: Icons.file_download_outlined,
                    label: 'Export',
                    onTap: onExport,
                  ),
                  const SizedBox(width: 8),
                  _SmallButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    primary: true,
                    onTap: onEdit,
                  ),
                ],
              ],
            ),
          ),
          if (emptyState != null) emptyState! else ...children,
          if (hasMore && !editing && onToggleExpanded != null)
            _ShowMoreFooter(expanded: expanded, onTap: onToggleExpanded!),
        ],
      ),
    );
  }
}

class _EnvViewRow extends StatelessWidget {
  const _EnvViewRow({
    required this.envKey,
    required this.value,
    required this.revealed,
    required this.onCopyKey,
    required this.onToggleReveal,
  });

  final String envKey;
  final String value;
  final bool revealed;
  final VoidCallback onCopyKey;
  final VoidCallback onToggleReveal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  envKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _EnvPalette.softText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _IconAction(
                icon: Icons.content_copy_outlined,
                tooltip: 'Copy key',
                onTap: onCopyKey,
              ),
              _IconAction(
                icon:
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                tooltip: revealed ? 'Hide value' : 'Reveal value',
                onTap: onToggleReveal,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _EnvPalette.input,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _EnvPalette.border.withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              revealed ? value : '••••••••••••',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceMono(
                fontSize: 11,
                letterSpacing: revealed ? 0 : 2,
                color: revealed ? _EnvPalette.text : _EnvPalette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvEditRow extends StatelessWidget {
  const _EnvEditRow({required this.entry, required this.onRemove});

  final _EnvDraftEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: entry.keyController,
                  focusNode: entry.keyFocusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _EnvPalette.text,
                  ),
                  decoration: _fieldDecoration(
                    hint: 'KEY',
                    errorText: entry.keyError,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                iconSize: 18,
                color: _EnvPalette.danger,
                tooltip: 'Remove variable',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: entry.valueController,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            style: GoogleFonts.spaceMono(fontSize: 12, color: _EnvPalette.text),
            decoration: _fieldDecoration(hint: 'VALUE'),
          ),
        ],
      ),
    );
  }
}

class _EmptyVariables extends StatelessWidget {
  const _EmptyVariables({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          const Icon(Icons.key_outlined, size: 24, color: _EnvPalette.muted),
          const SizedBox(height: 10),
          Text(
            'No environment variables yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceMono(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _EnvPalette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a key/value pair to configure this project.',
            textAlign: TextAlign.center,
            style: _bodyStyle,
          ),
          const SizedBox(height: 14),
          _SmallButton(
            icon: Icons.add,
            label: 'Add Group',
            primary: true,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _ShowMoreFooter extends StatelessWidget {
  const _ShowMoreFooter({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _EnvPalette.footer,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _EnvPalette.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_double_arrow_up
                    : Icons.keyboard_double_arrow_down,
                size: 16,
                color: _EnvPalette.muted,
              ),
              const SizedBox(width: 6),
              Text(
                expanded ? 'Show less' : 'Show more',
                style: GoogleFonts.spaceMono(
                  fontSize: 11,
                  color: _EnvPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// SHARED WIDGETS
// ==========================================
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background =
        primary
            ? _EnvPalette.primary
            : _EnvPalette.border.withValues(alpha: 0.9);
    final foreground = primary ? _EnvPalette.onPrimary : _EnvPalette.softText;

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side:
              primary
                  ? BorderSide.none
                  : const BorderSide(color: _EnvPalette.borderStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: foreground),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                      color: foreground,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailing, size: 14, color: _EnvPalette.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background = primary ? _EnvPalette.primary : _EnvPalette.border;
    final foreground = primary ? _EnvPalette.onPrimary : _EnvPalette.softText;

    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side:
              primary
                  ? BorderSide.none
                  : const BorderSide(color: _EnvPalette.borderStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: foreground),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: GoogleFonts.spaceMono(
                    fontSize: 11,
                    fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 16,
      color: _EnvPalette.muted,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        foregroundColor: _EnvPalette.muted,
        highlightColor: _EnvPalette.border,
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.label, {this.purple = false});

  final String label;
  final bool purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: purple ? _EnvPalette.purpleFill : _EnvPalette.border,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: purple ? _EnvPalette.purpleBorder : _EnvPalette.borderStrong,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: purple ? _EnvPalette.purpleText : _EnvPalette.softText,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? _EnvPalette.success : _EnvPalette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            live
                ? _EnvPalette.successFill
                : _EnvPalette.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color:
              live
                  ? _EnvPalette.successBorder
                  : _EnvPalette.borderStrong.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            live ? 'Live' : 'Stopped',
            style: GoogleFonts.spaceMono(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: _EnvPalette.border.withValues(alpha: 0.8),
    );
  }
}

class _MissingProject extends StatelessWidget {
  const _MissingProject();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'This project is no longer available.',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceMono(fontSize: 12, color: _EnvPalette.muted),
        ),
      ),
    );
  }
}

// ==========================================
// BUILDIFY MARK
// ==========================================
class _BuildifyMark extends StatelessWidget {
  const _BuildifyMark({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _BuildifyMarkPainter(_EnvPalette.text),
    );
  }
}

class _BuildifyMarkPainter extends CustomPainter {
  const _BuildifyMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale);

    final fill =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;

    canvas.drawRect(const Rect.fromLTWH(25, 15, 8, 70), fill);

    RRect server(double top, double width) => RRect.fromRectAndRadius(
      Rect.fromLTWH(33, top, width, 18),
      const Radius.circular(2),
    );

    canvas.drawRRect(server(15, 42), stroke);
    canvas.drawCircle(const Offset(65, 24), 3, fill);
    canvas.drawRRect(server(41, 35), stroke);
    canvas.drawCircle(const Offset(58, 50), 3, fill);
    canvas.drawRRect(server(67, 42), stroke);
    canvas.drawCircle(const Offset(65, 76), 3, fill);

    final curve =
        Path()
          ..moveTo(75, 50)
          ..cubicTo(85, 50, 85, 70, 75, 75);
    canvas.drawPath(
      curve,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BuildifyMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ==========================================
// DRAFT MODEL
// ==========================================
class _EnvDraftEntry {
  _EnvDraftEntry({String key = '', String value = ''})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;
  final FocusNode keyFocusNode = FocusNode();
  String? keyError;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
    keyFocusNode.dispose();
  }
}

// ==========================================
// HELPERS
// ==========================================
InputDecoration _fieldDecoration({required String hint, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.spaceMono(
      fontSize: 11,
      letterSpacing: 1,
      color: _EnvPalette.muted,
    ),
    errorText: errorText,
    errorStyle: GoogleFonts.spaceMono(fontSize: 10, color: _EnvPalette.danger),
    isDense: true,
    filled: true,
    fillColor: _EnvPalette.input,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    border: _envBorder(),
    enabledBorder: _envBorder(),
    focusedBorder: _envBorder(color: _EnvPalette.softText),
    errorBorder: _envBorder(color: _EnvPalette.danger),
    focusedErrorBorder: _envBorder(color: _EnvPalette.danger),
  );
}

OutlineInputBorder _envBorder({Color color = _EnvPalette.border}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color),
  );
}

String _providerLabel(String value) {
  switch (value.toLowerCase()) {
    case 'github':
      return 'GitHub';
    case 'gitlab':
      return 'GitLab';
    case 'docker':
      return 'Docker';
    case 'local':
      return 'Local';
    case '':
      return 'Project';
    default:
      return value[0].toUpperCase() + value.substring(1);
  }
}

const _breadcrumbStyle = TextStyle(
  fontSize: 11,
  height: 1.2,
  color: _EnvPalette.muted,
);

const _bodyStyle = TextStyle(
  fontSize: 12,
  height: 1.5,
  color: _EnvPalette.muted,
);

// ==========================================
// PALETTE
// ==========================================
class _EnvPalette {
  static const background = Color(0xFF131312);
  static const serviceHeader = Color(0xFF151514);
  static const card = Color(0xFF18181B);
  static const elevated = Color(0xFF1C1C20);
  static const footer = Color(0xFF141416);
  static const input = Color(0xFF121214);
  static const border = Color(0xFF27272A);
  static const borderStrong = Color(0xFF3F3F46);
  static const text = Color(0xFFF4F4F5);
  static const softText = Color(0xFFD4D4D8);
  static const muted = Color(0xFF71717A);
  static const primary = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFF000000);
  static const success = Color(0xFF34D399);
  static const successFill = Color(0xFF052E22);
  static const successBorder = Color(0xFF065F46);
  static const purpleText = Color(0xFFD8B4FE);
  static const purpleFill = Color(0xFF2E1065);
  static const purpleBorder = Color(0xFF6B21A8);
  static const danger = Color(0xFFF87171);
  static const selection = Color(0x553F3F46);
}
