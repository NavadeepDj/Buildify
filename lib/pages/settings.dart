import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/embedded_backend.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import '../services/subdomain.dart';
import 'env_management_page.dart';

// ==========================================
// SHARED SETTINGS DROPDOWN
// ==========================================
class ProjectSettingsMenuButton extends StatelessWidget {
  const ProjectSettingsMenuButton({
    super.key,
    required this.onOpenEnvironment,
    required this.onOpenSettings,
    this.icon = Icons.settings_outlined,
    this.iconColor,
    this.iconSize = 20,
  });

  final VoidCallback onOpenEnvironment;
  final VoidCallback onOpenSettings;
  final IconData icon;
  final Color? iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Project settings',
      icon: Icon(
        icon,
        size: iconSize,
        color: iconColor ?? _SettingsPalette.onSurfaceVariant,
      ),
      color: _SettingsPalette.surfaceContainer,
      elevation: 10,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: _SettingsPalette.outlineVariant),
      ),
      onSelected: (value) {
        if (value == 'environment') onOpenEnvironment();
        if (value == 'settings') onOpenSettings();
      },
      itemBuilder:
          (context) => [
            _menuItem('environment', Icons.key_outlined, 'Environment'),
            _menuItem('settings', Icons.settings_outlined, 'Settings'),
          ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: 180,
        child: Row(
          children: [
            Icon(icon, size: 16, color: _SettingsPalette.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  color: _SettingsPalette.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PROJECT SETTINGS PAGE
// ==========================================
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _scrollController = ScrollController();
  final _generalKey = GlobalKey();
  final _buildKey = GlobalKey();
  final _deployKey = GlobalKey();
  final _domainsKey = GlobalKey();
  final _previewsKey = GlobalKey();
  final _networkingKey = GlobalKey();
  final _healthKey = GlobalKey();
  final _dangerKey = GlobalKey();

  String _activeSection = 'general';
  bool _busy = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _SettingsPalette.surfaceContainerHigh,
        content: Text(
          message,
          style: GoogleFonts.spaceMono(
            fontSize: 12,
            color: _SettingsPalette.onSurface,
          ),
        ),
      ),
    );
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showMessage(message);
  }

  Future<void> _openUrl(String value) async {
    final normalized = _normalizeUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      _showMessage('Invalid URL');
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) return;
    _showMessage('URL copied (could not open browser)');
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualDeploy(BackendProject project) async {
    await _runBusy(() async {
      try {
        await ref
            .read(embeddedBackendProvider)
            .startSession(projectId: project.id);
        if (mounted) _showMessage('Deployment started');
      } catch (error) {
        if (mounted) _showMessage('Deployment failed: $error');
      }
    });
  }

  Future<void> _editName(BackendProject project) async {
    final value = await _promptForText(
      title: 'Edit Service Name',
      label: 'Choose a unique name for this web service.',
      initialValue: project.name,
      hint: 'Service name',
      validator: (value) => value.trim().isEmpty ? 'Name is required' : null,
    );
    if (value == null) return;
    try {
      await ref
          .read(embeddedBackendProvider)
          .updateProjectName(project.id, value);
      if (mounted) _showMessage('Service name updated');
    } catch (error) {
      if (mounted) _showMessage('Could not update name: $error');
    }
  }

  Future<void> _editBranch(BackendProject project) async {
    final value = await _promptForText(
      title: 'Edit Branch',
      label: 'Builds and deploys use this repository branch.',
      initialValue: project.branch,
      hint: 'main',
      validator: (value) => value.trim().isEmpty ? 'Branch is required' : null,
    );
    if (value == null) return;
    await _updateBuildConfig(project, branch: value);
  }

  Future<void> _editRootDirectory(BackendProject project) async {
    final value = await _promptForText(
      title: 'Edit Root Directory',
      label: 'Relative path inside the repository to build from.',
      initialValue: project.baseDir,
      hint: '.',
    );
    if (value == null) return;
    await _updateBuildConfig(project, baseDir: value);
  }

  Future<void> _updateBuildConfig(
    BackendProject project, {
    String? branch,
    String? baseDir,
  }) async {
    try {
      await ref
          .read(embeddedBackendProvider)
          .updateBuildConfig(project.id, branch: branch, baseDir: baseDir);
      if (mounted) _showMessage('Build configuration updated');
    } catch (error) {
      if (mounted) _showMessage('Could not update build config: $error');
    }
  }

  Future<void> _editSubdomain(BackendProject project) async {
    final controller = TextEditingController(text: project.subdomain);
    final service = ref.read(embeddedBackendProvider).liveUrls;
    String? error;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, update) => AlertDialog(
                  backgroundColor: _SettingsPalette.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                      color: _SettingsPalette.outlineVariant,
                    ),
                  ),
                  title: Text(
                    'Edit Subdomain',
                    style: GoogleFonts.spaceMono(
                      color: _SettingsPalette.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: TextField(
                    controller: controller,
                    enabled: !saving,
                    style: GoogleFonts.spaceMono(
                      color: _SettingsPalette.onSurface,
                    ),
                    onChanged:
                        (value) =>
                            update(() => error = validateSubdomain(value)),
                    decoration: InputDecoration(
                      suffixText: '.$baseDomain',
                      suffixStyle: GoogleFonts.spaceMono(
                        color: _SettingsPalette.outline,
                      ),
                      errorText: error,
                      filled: true,
                      fillColor: _SettingsPalette.surfaceContainerLow,
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _SettingsPalette.outlineVariant,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: _SettingsPalette.primary),
                      ),
                    ),
                  ),
                  actions: [
                    _DialogAction(
                      label: 'CANCEL',
                      onTap: saving ? null : () => Navigator.pop(ctx),
                    ),
                    _DialogAction(
                      label: saving ? 'SAVING…' : 'SAVE',
                      primary: true,
                      onTap:
                          saving
                              ? null
                              : () async {
                                final name = controller.text;
                                final validation = validateSubdomain(name);
                                if (validation != null) {
                                  update(() => error = validation);
                                  return;
                                }
                                update(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await service.assign(
                                    project.id,
                                    custom: name,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    update(() {
                                      saving = false;
                                      error = '$e';
                                    });
                                  }
                                }
                              },
                    ),
                  ],
                ),
          ),
    );
    controller.dispose();
  }

  Future<void> _delete(BackendProject project) async {
    var canDelete = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, update) => AlertDialog(
                  backgroundColor: _SettingsPalette.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                      color: _SettingsPalette.outlineVariant,
                    ),
                  ),
                  title: Text(
                    'Delete ${project.name}?',
                    style: GoogleFonts.spaceMono(
                      color: _SettingsPalette.error,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This permanently removes the project, its configuration, environment variables, and delivery history.',
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          height: 1.5,
                          color: _SettingsPalette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Type '),
                            TextSpan(
                              text: project.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _SettingsPalette.primary,
                              ),
                            ),
                            const TextSpan(text: ' to confirm.'),
                          ],
                        ),
                        style: GoogleFonts.spaceMono(
                          fontSize: 11,
                          color: _SettingsPalette.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        autofocus: true,
                        style: GoogleFonts.spaceMono(
                          color: _SettingsPalette.onSurface,
                        ),
                        onChanged:
                            (value) => update(
                              () => canDelete = value.trim() == project.name,
                            ),
                        decoration: InputDecoration(
                          hintText: project.name,
                          hintStyle: GoogleFonts.spaceMono(
                            color: _SettingsPalette.outline,
                          ),
                          filled: true,
                          fillColor: _SettingsPalette.surfaceContainerLow,
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.outlineVariant,
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    _DialogAction(
                      label: 'CANCEL',
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                    _DialogAction(
                      label: 'DELETE',
                      destructive: true,
                      onTap: canDelete ? () => Navigator.pop(ctx, true) : null,
                    ),
                  ],
                ),
          ),
    );
    if (confirmed != true) return;
    await _runBusy(() async {
      try {
        await ref.read(embeddedBackendProvider).deleteProject(project.id);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (error) {
        if (mounted) _showMessage('Could not delete project: $error');
      }
    });
  }

  Future<String?> _promptForText({
    required String title,
    required String label,
    required String initialValue,
    String? hint,
    String? Function(String value)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, update) => AlertDialog(
                  backgroundColor: _SettingsPalette.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                      color: _SettingsPalette.outlineVariant,
                    ),
                  ),
                  title: Text(
                    title,
                    style: GoogleFonts.spaceMono(
                      color: _SettingsPalette.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.spaceMono(
                          fontSize: 11,
                          height: 1.5,
                          color: _SettingsPalette.outline,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        style: GoogleFonts.spaceMono(
                          color: _SettingsPalette.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: GoogleFonts.spaceMono(
                            color: _SettingsPalette.outline,
                          ),
                          errorText: error,
                          errorStyle: GoogleFonts.spaceMono(
                            fontSize: 10,
                            color: _SettingsPalette.error,
                          ),
                          filled: true,
                          fillColor: _SettingsPalette.surfaceContainerLow,
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.outlineVariant,
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.primary,
                            ),
                          ),
                          errorBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.error,
                            ),
                          ),
                          focusedErrorBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _SettingsPalette.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    _DialogAction(
                      label: 'CANCEL',
                      onTap: () => Navigator.pop(ctx),
                    ),
                    _DialogAction(
                      label: 'SAVE',
                      primary: true,
                      onTap: () {
                        final value = controller.text.trim();
                        final validation = validator?.call(value);
                        if (validation != null) {
                          update(() => error = validation);
                          return;
                        }
                        Navigator.pop(ctx, value);
                      },
                    ),
                  ],
                ),
          ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _scrollTo(GlobalKey key, String id) async {
    setState(() => _activeSection = id);
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(embeddedBackendProvider);
    final state = ref.watch(backendStateProvider).value ?? service.state;
    final matches = state.projects.where((p) => p.id == widget.projectId);
    final project = matches.isEmpty ? null : matches.first;
    final device = ref.watch(aiServerProvider).device;

    final horizontalPadding =
        MediaQuery.sizeOf(context).width >= 768 ? 32.0 : 16.0;
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 32;

    final targets = <_JumpTarget>[
      _JumpTarget('general', 'General', _generalKey),
      _JumpTarget('build', 'Build', _buildKey),
      _JumpTarget('deploy', 'Deploy', _deployKey),
      _JumpTarget('domains', 'Domains', _domainsKey),
      _JumpTarget('previews', 'PR Previews', _previewsKey),
      _JumpTarget('networking', 'Networking', _networkingKey),
      _JumpTarget('health', 'Health Checks', _healthKey),
      _JumpTarget('danger', 'Danger Zone', _dangerKey, danger: true),
    ];

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _SettingsPalette.background,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _SettingsPalette.primary,
          selectionColor: Color(0x55444748),
          selectionHandleColor: _SettingsPalette.primary,
        ),
      ),
      child: Scaffold(
        backgroundColor: _SettingsPalette.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _SettingsTopBar(
                projectName: project?.name ?? '',
                horizontalPadding: horizontalPadding,
                onBack: () => Navigator.of(context).maybePop(),
                onOpenEnvironment:
                    project == null
                        ? null
                        : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => EnvManagementPage(projectId: project.id),
                          ),
                        ),
                onOpenSettings: () {},
              ),
              Expanded(
                child:
                    project == null
                        ? const _MissingProject()
                        : _buildSettings(
                          project: project,
                          state: state,
                          device: device,
                          horizontalPadding: horizontalPadding,
                          bottomPadding: bottomPadding,
                          targets: targets,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettings({
    required BackendProject project,
    required BackendState state,
    required DeviceSnapshot device,
    required double horizontalPadding,
    required double bottomPadding,
    required List<_JumpTarget> targets,
  }) {
    final session = state.activeSession;
    final isActive = session != null && session.projectId == project.id;
    final rawEndpoint =
        project.liveUrl.isNotEmpty
            ? project.liveUrl
            : (isActive ? session.publicUrl : 'localhost:${project.port}');
    final endpoint = _normalizeUrl(rawEndpoint);
    final subdomainHost =
        project.subdomain.isNotEmpty
            ? '${project.subdomain}.$baseDomain'
            : '${projectNameSubdomain(project.name)}.$baseDomain';
    final subdomainUrl = 'https://$subdomainHost';
    final serviceId = 'web-${project.port}';
    final provider = _providerLabel(project.repoProvider);
    final repoUrl = project.url.trim();
    final repoLabel = repoUrl.isEmpty ? project.name : _shortRepoLabel(repoUrl);
    final branch =
        project.branch.trim().isEmpty ? 'main' : project.branch.trim();
    final baseDir = project.baseDir.trim();
    final dockerfile = '${baseDir.isEmpty ? '' : '$baseDir/'}Dockerfile';
    final buildContext = baseDir.isEmpty ? '.' : baseDir;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _SettingsHero(
              projectName: project.name,
              provider: provider,
              isLive: project.isLive,
              serviceId: serviceId,
              repoLabel: repoLabel,
              branch: branch,
              subdomainUrl: subdomainUrl,
              busy: _busy,
              onConnect: () => _copy(endpoint, 'Endpoint copied'),
              onDeploy: () => _manualDeploy(project),
              onCopyId: () => _copy(serviceId, 'Service ID copied'),
              onCopyUrl: () => _copy(subdomainUrl, 'URL copied'),
              onOpenUrl: () => _openUrl(subdomainUrl),
              onOpenRepo: () {
                if (repoUrl.isEmpty) {
                  _showMessage('No repository URL configured');
                  return;
                }
                _openUrl(repoUrl);
              },
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _QuickJumpHeaderDelegate(
            activeSection: _activeSection,
            horizontalPadding: horizontalPadding,
            targets: targets,
            onSelect: (target) => _scrollTo(target.key, target.id),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            bottomPadding,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsSection(
                  key: _generalKey,
                  title: 'General',
                  index: 'Config_01',
                  children: [
                    _SettingsField(
                      label: 'Service Name',
                      description: 'A unique name for your Web Service.',
                      action: _EditAction(onTap: () => _editName(project)),
                      value: _ValueBox(
                        trailing: const Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: _SettingsPalette.outline,
                        ),
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _monoStyle(
                            fontSize: 14,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Region',
                      description: 'Internal private networking zone.',
                      tag: const _MicroTag('LOCKED'),
                      value: _ValueBox(
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: _SettingsPalette.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Local Device',
                              style: _monoStyle(
                                fontSize: 14,
                                color: _SettingsPalette.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Instance Type',
                      tag: _MicroTag('${device.ramGb} GB RAM'),
                      value: _ValueBox(
                        child: Text(
                          '${device.cpuLabel} · ${device.ramGb} GB RAM',
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _InfoCallout(
                      message:
                          'Hosting runs on this device. Keep Buildify open while the service is live so it stays reachable.',
                    ),
                    const _FreeRuntimeBanner(),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  key: _buildKey,
                  title: 'Build',
                  index: 'Config_02',
                  children: [
                    _SettingsField(
                      label: 'Source Repository',
                      description: 'The repository Buildify builds from.',
                      action: _EditAction(
                        label: 'Open',
                        icon: Icons.open_in_new,
                        onTap: () {
                          if (repoUrl.isEmpty) {
                            _showMessage('No repository URL configured');
                            return;
                          }
                          _openUrl(repoUrl);
                        },
                      ),
                      value: _ValueBox(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.code,
                              size: 16,
                              color: _SettingsPalette.outline,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                repoLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _monoStyle(
                                  fontSize: 13,
                                  color: _SettingsPalette.onSurface,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: _SettingsPalette.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Branch',
                      description: 'The branch built on every deployment.',
                      action: _EditAction(onTap: () => _editBranch(project)),
                      value: _ValueBox(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.alt_route,
                              size: 16,
                              color: _SettingsPalette.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              branch,
                              style: _monoStyle(
                                fontSize: 13,
                                color: _SettingsPalette.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (branch == 'main') const _MicroTag('DEFAULT'),
                          ],
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Root Directory',
                      description:
                          'Relative path inside the repository to build from.',
                      action: _EditAction(
                        onTap: () => _editRootDirectory(project),
                      ),
                      value: _ValueBox(
                        child: Text(
                          baseDir.isEmpty ? '.' : baseDir,
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Dockerfile Path',
                      description:
                          'Detected from the root directory for Docker projects.',
                      value: _ValueBox(
                        child: Text(
                          dockerfile,
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Docker Build Context',
                      description: 'Directory sent to the Docker builder.',
                      value: _ValueBox(
                        child: Text(
                          buildContext,
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Build Filters',
                      description:
                          'All repository paths are included for local builds.',
                      tag: const _MicroTag('SMART-TRIGGER'),
                      value: _ValueBox(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FilterRow(
                              label: 'Included Paths:',
                              values: ['**'],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ignored Paths: None',
                              style: GoogleFonts.spaceMono(
                                fontSize: 10,
                                color: _SettingsPalette.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  key: _deployKey,
                  title: 'Deploy',
                  index: 'Config_03',
                  children: [
                    _SettingsField(
                      label: 'Auto-Deploy',
                      description:
                          'Deploys are triggered manually from the service header.',
                      tag: const _MicroTag('MANUAL'),
                      value: _ValueBox(
                        trailing: TextButton(
                          onPressed:
                              _busy ? null : () => _manualDeploy(project),
                          style: TextButton.styleFrom(
                            foregroundColor: _SettingsPalette.secondary,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: GoogleFonts.spaceMono(
                              fontSize: 10,
                              height: 1.4,
                            ),
                          ),
                          child: const Text('Deploy now'),
                        ),
                        child: Text(
                          'Manual deploy only',
                          style: _monoStyle(
                            fontSize: 13,
                            color: _SettingsPalette.onSurface,
                          ),
                        ),
                      ),
                    ),
                    _SettingsField(
                      label: 'Deploy Hook',
                      description:
                          'HTTP POST endpoint to trigger builds from CI/CD pipelines. Deploy hooks are not available for local hosting.',
                      tag: const _MicroTag('LOCAL ONLY'),
                      value: _ValueBox(
                        trailing: const Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: _SettingsPalette.outline,
                        ),
                        child: Text(
                          '••••••••••••••••••••••••••••••••',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  key: _domainsKey,
                  title: 'Domains & Network',
                  index: 'Config_04',
                  children: [
                    _SettingsField(
                      label: 'Default Subdomain',
                      description: 'System-assigned Buildify host.',
                      action: _EditAction(onTap: () => _editSubdomain(project)),
                      value: _ValueBox(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                subdomainHost,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _monoStyle(
                                  fontSize: 12,
                                  color: _SettingsPalette.primary,
                                ),
                              ),
                            ),
                            _TinyIconAction(
                              icon: Icons.content_copy,
                              tooltip: 'Copy URL',
                              onTap: () => _copy(subdomainUrl, 'URL copied'),
                            ),
                            _TinyIconAction(
                              icon: Icons.open_in_new,
                              tooltip: 'Open URL',
                              onTap: () => _openUrl(subdomainUrl),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.verified_outlined,
                              size: 16,
                              color: _SettingsPalette.success,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _WideButton(
                      label: 'Add Custom Domain',
                      icon: Icons.add_circle_outline,
                      onTap:
                          () => _showMessage(
                            'Custom domains are not available yet.',
                          ),
                    ),
                    _EdgeCachingCard(
                      key: _networkingKey,
                      onUpgrade:
                          () => _showMessage(
                            'Edge caching is not available on this plan.',
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  key: _healthKey,
                  title: 'Health & Maintenance',
                  index: 'Config_05',
                  children: [
                    _SettingsField(
                      label: 'Health Check Path',
                      description:
                          'The service root is used as the liveness endpoint.',
                      value: _ValueBox(
                        trailing: Icon(
                          project.isLive
                              ? Icons.check_circle_outline
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color:
                              project.isLive
                                  ? _SettingsPalette.success
                                  : _SettingsPalette.outline,
                        ),
                        child: Text(
                          '/',
                          style: _monoStyle(
                            fontSize: 12,
                            color: _SettingsPalette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    _ToggleRow(
                      key: _previewsKey,
                      label: 'PR Previews',
                      description:
                          'Preview environments for pull requests are not supported for local hosting.',
                      tag: const _MicroTag('NOT CONFIGURED'),
                    ),
                    const _ToggleRow(
                      label: 'Maintenance Mode',
                      description:
                          'Serving a static 503 standby response is not supported for local hosting.',
                      tag: _MicroTag('UNAVAILABLE'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  key: _dangerKey,
                  title: 'Danger Zone',
                  danger: true,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IRREVERSIBLE ACTIONS',
                          style: _labelCaps(color: _SettingsPalette.error),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Deleting tears down the project configuration, environment variables, and delivery history permanently.',
                          style: GoogleFonts.spaceMono(
                            fontSize: 10,
                            height: 1.5,
                            color: _SettingsPalette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    _WideButton(
                      label: 'Delete Web Service',
                      icon: Icons.delete_forever_outlined,
                      background: _SettingsPalette.errorRed.withValues(
                        alpha: 0.2,
                      ),
                      foreground: _SettingsPalette.error,
                      onTap: _busy ? null : () => _delete(project),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TOP BAR
// ==========================================
class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({
    required this.projectName,
    required this.horizontalPadding,
    required this.onBack,
    required this.onOpenEnvironment,
    required this.onOpenSettings,
  });

  final String projectName;
  final double horizontalPadding;
  final VoidCallback onBack;
  final VoidCallback? onOpenEnvironment;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final fallbackEnvironment = onOpenEnvironment;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding - 8,
        8,
        horizontalPadding,
        8,
      ),
      color: _SettingsPalette.background,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            iconSize: 20,
            color: _SettingsPalette.onSurfaceVariant,
            tooltip: 'Go back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          ),
          const SizedBox(width: 4),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _SettingsPalette.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '>_',
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _SettingsPalette.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    projectName.isEmpty ? 'project' : projectName.toLowerCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: _SettingsPalette.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '/',
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: _SettingsPalette.outline,
                    ),
                  ),
                ),
                Text(
                  'Settings',
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _SettingsPalette.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ProjectSettingsMenuButton(
            onOpenEnvironment: fallbackEnvironment ?? () {},
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// HERO
// ==========================================
class _SettingsHero extends StatelessWidget {
  const _SettingsHero({
    required this.projectName,
    required this.provider,
    required this.isLive,
    required this.serviceId,
    required this.repoLabel,
    required this.branch,
    required this.subdomainUrl,
    required this.busy,
    required this.onConnect,
    required this.onDeploy,
    required this.onCopyId,
    required this.onCopyUrl,
    required this.onOpenUrl,
    required this.onOpenRepo,
  });

  final String projectName;
  final String provider;
  final bool isLive;
  final String serviceId;
  final String repoLabel;
  final String branch;
  final String subdomainUrl;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDeploy;
  final VoidCallback onCopyId;
  final VoidCallback onCopyUrl;
  final VoidCallback onOpenUrl;
  final VoidCallback onOpenRepo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _HeroBadge(label: 'Web Service'),
            _HeroBadge(
              label: provider,
              icon: Icons.layers_outlined,
              foreground: _SettingsPalette.primary,
            ),
            const _HeroBadge(
              label: 'Free Plan',
              background: _SettingsPalette.secondaryContainer,
              foreground: _SettingsPalette.onSecondaryContainer,
            ),
            _LiveBadge(live: isLive),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              projectName,
              style: GoogleFonts.spaceMono(
                fontSize: 24,
                height: 32 / 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.48,
                color: _SettingsPalette.primary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroAction(
                  label: 'Connect',
                  trailing: Icons.expand_more,
                  onTap: onConnect,
                ),
                const SizedBox(width: 8),
                _HeroAction(
                  label: busy ? 'Deploying…' : 'Manual Deploy',
                  icon: Icons.bolt,
                  primary: true,
                  onTap: busy ? null : onDeploy,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _HeroMetaRow(
          child: Row(
            children: [
              Text(
                'ID:',
                style: _monoStyle(
                  fontSize: 10,
                  color: _SettingsPalette.outline,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  serviceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoStyle(
                    fontSize: 10,
                    color: _SettingsPalette.onSurface,
                  ),
                ),
              ),
              _TinyIconAction(
                icon: Icons.content_copy,
                tooltip: 'Copy service ID',
                onTap: onCopyId,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _HeroMetaRow(
          child: Row(
            children: [
              const Icon(
                Icons.fork_right,
                size: 14,
                color: _SettingsPalette.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  repoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoStyle(
                    fontSize: 10,
                    color: _SettingsPalette.onSurface,
                  ),
                ),
              ),
              _MicroTag(branch),
              _TinyIconAction(
                icon: Icons.terminal,
                tooltip: 'Open repository',
                onTap: onOpenRepo,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _HeroMetaRow(
          child: Row(
            children: [
              const Icon(Icons.link, size: 14, color: _SettingsPalette.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subdomainUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoStyle(
                    fontSize: 10,
                    color: _SettingsPalette.primary,
                  ),
                ),
              ),
              _TinyIconAction(
                icon: Icons.content_copy,
                tooltip: 'Copy URL',
                onTap: onCopyUrl,
              ),
              _TinyIconAction(
                icon: Icons.open_in_new,
                tooltip: 'Open URL',
                onTap: onOpenUrl,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.label,
    this.icon,
    this.background = _SettingsPalette.surfaceContainerHigh,
    this.foreground = _SettingsPalette.onSurfaceVariant,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              height: 10 / 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final color =
        live ? _SettingsPalette.success : _SettingsPalette.statusSuspended;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            live
                ? _SettingsPalette.successContainer.withValues(alpha: 0.4)
                : _SettingsPalette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
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
            live ? 'LIVE' : 'STOPPED',
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              height: 10 / 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
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
    final foreground =
        primary ? _SettingsPalette.onPrimary : _SettingsPalette.primary;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor:
            primary
                ? _SettingsPalette.primary
                : _SettingsPalette.surfaceContainerHigh,
        foregroundColor: foreground,
        disabledBackgroundColor:
            primary
                ? _SettingsPalette.primary.withValues(alpha: 0.5)
                : _SettingsPalette.surfaceContainerHigh,
        disabledForegroundColor: foreground.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
          Text(label),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(trailing, size: 14, color: _SettingsPalette.onSurfaceVariant),
          ],
        ],
      ),
    );
  }
}

class _HeroMetaRow extends StatelessWidget {
  const _HeroMetaRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _SettingsPalette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

// ==========================================
// QUICK JUMP NAV
// ==========================================
class _JumpTarget {
  const _JumpTarget(this.id, this.label, this.key, {this.danger = false});

  final String id;
  final String label;
  final GlobalKey key;
  final bool danger;
}

class _QuickJumpHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _QuickJumpHeaderDelegate({
    required this.activeSection,
    required this.horizontalPadding,
    required this.targets,
    required this.onSelect,
  });

  final String activeSection;
  final double horizontalPadding;
  final List<_JumpTarget> targets;
  final void Function(_JumpTarget target) onSelect;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: maxExtent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: _SettingsPalette.background.withValues(alpha: 0.82),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                children: [
                  for (final target in targets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _JumpChip(
                        label: target.label,
                        danger: target.danger,
                        active: activeSection == target.id,
                        onTap: () => onSelect(target),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _QuickJumpHeaderDelegate oldDelegate) {
    return oldDelegate.activeSection != activeSection ||
        oldDelegate.horizontalPadding != horizontalPadding;
  }
}

class _JumpChip extends StatelessWidget {
  const _JumpChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background =
        active
            ? (danger
                ? _SettingsPalette.errorRed.withValues(alpha: 0.75)
                : _SettingsPalette.primary)
            : (danger
                ? _SettingsPalette.errorContainer.withValues(alpha: 0.4)
                : _SettingsPalette.surfaceContainerHigh);
    final foreground =
        active
            ? (danger ? _SettingsPalette.error : _SettingsPalette.onPrimary)
            : (danger ? _SettingsPalette.error : _SettingsPalette.onSurface);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              height: 12 / 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// SECTION BUILDING BLOCKS
// ==========================================
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.index,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final String? index;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) content.add(const SizedBox(height: 16));
      content.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color:
                    danger
                        ? _SettingsPalette.errorRed
                        : _SettingsPalette.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.spaceMono(
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.36,
                color:
                    danger ? _SettingsPalette.error : _SettingsPalette.primary,
              ),
            ),
            const Spacer(),
            if (index != null)
              Text(
                index!.toUpperCase(),
                style: GoogleFonts.spaceMono(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: _SettingsPalette.outline,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                danger
                    ? _SettingsPalette.surfaceContainerLowest
                    : _SettingsPalette.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            gradient:
                danger
                    ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _SettingsPalette.errorContainer.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    )
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      ],
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.value,
    this.description,
    this.action,
    this.tag,
  });

  final String label;
  final Widget value;
  final String? description;
  final Widget? action;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: _labelCaps())),
            if (tag != null) tag!,
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              height: 1.4,
              color: _SettingsPalette.outline,
            ),
          ),
        ],
        const SizedBox(height: 8),
        value,
      ],
    );
  }
}

class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.child, this.trailing, this.padding});

  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _SettingsPalette.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _EditAction extends StatelessWidget {
  const _EditAction({
    required this.onTap,
    this.label = 'Edit',
    this.icon = Icons.edit_outlined,
  });

  final VoidCallback? onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _SettingsPalette.secondary,
        disabledForegroundColor: _SettingsPalette.outline,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: GoogleFonts.spaceMono(fontSize: 10, height: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 13), const SizedBox(width: 4), Text(label)],
      ),
    );
  }
}

class _MicroTag extends StatelessWidget {
  const _MicroTag(
    this.text, {
    this.background = _SettingsPalette.surfaceContainerHigh,
    this.foreground = _SettingsPalette.outline,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.spaceMono(
          fontSize: 8,
          height: 10 / 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: foreground,
        ),
      ),
    );
  }
}

class _TinyIconAction extends StatelessWidget {
  const _TinyIconAction({
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
      color: _SettingsPalette.onSurfaceVariant,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SettingsPalette.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: _SettingsPalette.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                height: 1.5,
                color: _SettingsPalette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeRuntimeBanner extends StatelessWidget {
  const _FreeRuntimeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _SettingsPalette.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_top,
            size: 18,
            color: _SettingsPalette.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Local runtime: '),
                  const TextSpan(
                    text: 'no monthly hour cap',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _SettingsPalette.primary,
                    ),
                  ),
                ],
              ),
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                height: 1.4,
                color: _SettingsPalette.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final messenger = ScaffoldMessenger.of(context);
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: _SettingsPalette.surfaceContainerHigh,
                  content: Text(
                    'This project runs on your device at no additional hosting cost.',
                    style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      color: _SettingsPalette.onSurface,
                    ),
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: _SettingsPalette.primary,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: GoogleFonts.spaceMono(fontSize: 10, height: 1.4),
            ),
            child: const Text('Details'),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 10,
            color: _SettingsPalette.outline,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _SettingsPalette.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  value,
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    color: _SettingsPalette.primary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _EdgeCachingCard extends StatelessWidget {
  const _EdgeCachingCard({super.key, required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SettingsPalette.surfaceContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_sync_outlined,
                size: 14,
                color: _SettingsPalette.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'EDGE CACHING',
                  style: _labelCaps(color: _SettingsPalette.primary),
                ),
              ),
              _MicroTag(
                'PAID ADD-ON',
                background: _SettingsPalette.errorRed.withValues(alpha: 0.2),
                foreground: _SettingsPalette.error,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cache high-throughput static assets and microservice endpoints across edge locations.',
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              height: 1.5,
              color: _SettingsPalette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status: Standard Pass-Through',
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    color: _SettingsPalette.outline,
                  ),
                ),
              ),
              TextButton(
                onPressed: onUpgrade,
                style: TextButton.styleFrom(
                  backgroundColor: _SettingsPalette.primary,
                  foregroundColor: _SettingsPalette.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  textStyle: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                child: const Text('UPGRADE'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.background = _SettingsPalette.surfaceContainerHigh,
    this.foreground = _SettingsPalette.primary,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledForegroundColor: foreground.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: GoogleFonts.spaceMono(
          fontSize: 10,
          height: 12 / 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.label,
    required this.description,
    this.tag,
  });

  final String label;
  final String description;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(label.toUpperCase(), style: _labelCaps()),
                  ),
                  if (tag != null) ...[const SizedBox(width: 8), tag!],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  height: 1.4,
                  color: _SettingsPalette.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: 0.82,
          child: const Switch(value: false, onChanged: null),
        ),
      ],
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final background =
        destructive
            ? _SettingsPalette.errorRed.withValues(alpha: 0.2)
            : (primary ? _SettingsPalette.primary : Colors.transparent);
    final foreground =
        destructive
            ? _SettingsPalette.error
            : (primary
                ? _SettingsPalette.onPrimary
                : _SettingsPalette.onSurfaceVariant);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledForegroundColor: foreground.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side:
              primary || destructive
                  ? BorderSide.none
                  : const BorderSide(color: _SettingsPalette.outlineVariant),
        ),
        textStyle: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      child: Text(label),
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
          style: GoogleFonts.spaceMono(
            fontSize: 12,
            color: _SettingsPalette.outline,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// HELPERS
// ==========================================
TextStyle _monoStyle({
  required double fontSize,
  required Color color,
  FontWeight fontWeight = FontWeight.w400,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.spaceMono(
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle _labelCaps({Color color = _SettingsPalette.primary}) {
  return GoogleFonts.spaceMono(
    fontSize: 10,
    height: 12 / 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: color,
  );
}

String _normalizeUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return 'http://$trimmed';
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
    case 'node':
    case 'nodejs':
    case 'node.js':
      return 'Node.js';
    case 'python':
    case 'python fastapi':
    case 'flask':
    case 'fastapi':
      return 'Python';
    case '':
      return 'Project';
    default:
      return value[0].toUpperCase() + value.substring(1);
  }
}

String _shortRepoLabel(String value) {
  var result = value.trim();
  if (result.isEmpty) return result;
  result = result.replaceFirst(RegExp(r'^https?://'), '');
  result = result.replaceFirst(RegExp(r'^www\.'), '');
  if (result.startsWith('github.com/')) {
    result = result.substring('github.com/'.length);
  }
  if (result.endsWith('.git')) {
    result = result.substring(0, result.length - 4);
  }
  return result;
}

// ==========================================
// PALETTE
// ==========================================
class _SettingsPalette {
  static const background = Color(0xFF131312);
  static const surfaceContainerLowest = Color(0xFF0E0E0D);
  static const surfaceContainerLow = Color(0xFF1C1C1A);
  static const surfaceContainer = Color(0xFF20201E);
  static const surfaceContainerHigh = Color(0xFF2A2A29);
  static const primary = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFF2F3131);
  static const onSurface = Color(0xFFE5E2E0);
  static const onSurfaceVariant = Color(0xFFC4C7C8);
  static const outline = Color(0xFF8E9192);
  static const outlineVariant = Color(0xFF444748);
  static const secondary = Color(0xFFC8C6C3);
  static const secondaryContainer = Color(0xFF474744);
  static const onSecondaryContainer = Color(0xFFB7B5B1);
  static const success = Color(0xFF34D399);
  static const successContainer = Color(0xFF003924);
  static const error = Color(0xFFFFB4AB);
  static const errorRed = Color(0xFFAF1D27);
  static const errorContainer = Color(0xFF93000A);
  static const statusSuspended = Color(0xFF897671);
}
