import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/embedded_backend.dart';
import '../providers/ai_server_provider.dart';
import '../services/guided_tour_service.dart';
import '../services/subdomain.dart';
import '../widgets/guided_tour_overlay.dart';
import 'env_management_page.dart';

// ==========================================
// PALETTE — MATCHING service_detail_page.dart
// ==========================================
class _DetailPalette {
  static const background = Color(0xFF131312);
  static const primary = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFFE5E2E0);
  static const onSurfaceVariant = Color(0xFFC4C7C8);
  static const onPrimary = Color(0xFF2F3131);
  static const outlineVariant = Color(0xFF444748);
  static const surfaceContainer = Color(0xFF20201E);
  static const surfaceContainerLow = Color(0xFF1C1C1A);
  static const surfaceContainerLowest = Color(0xFF0E0E0D);
  static const successGreen = Color(0xFF10B981);
  static const statusSuspended = Color(0xFF897671);
  static const terminalBg = Color(0xFF0E0E0D);
}

// ==========================================
// LOG LINE MODEL
// ==========================================
class _LogLine {
  const _LogLine(
    this.time,
    this.instance,
    this.message, {
    required this.createdAt,
    this.highlight = false,
    this.success = false,
    this.warning = false,
    this.dim = false,
  });

  final String time;
  final String instance;
  final String message;
  final DateTime createdAt;
  final bool highlight;
  final bool success;
  final bool warning;
  final bool dim;
}

// ==========================================
// PROJECT DETAIL PAGE
// ==========================================
class ProjectDetailPage extends ConsumerStatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends ConsumerState<ProjectDetailPage> {
  final _logSearchController = TextEditingController();
  final _logScrollController = ScrollController();
  int _lastLogCount = 0;
  bool _logsFullscreen = false;
  bool _showCustomRange = false;
  String _timeRange = 'last hour';

  final _controlKey = GlobalKey();
  final _endpointKey = GlobalKey();
  final _configKey = GlobalKey();
  final _logsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _logSearchController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final steps = [
        GuidedTourStep(
          title: 'Start & Stop Hosting',
          description:
              'Tap Start Server to launch this project and open a public tunnel. Tap again to stop it anytime.',
          targetKey: _controlKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Your Live Endpoint',
          description:
              'Once online, share or open your public URL here. Copy it or launch it in a browser with one tap.',
          targetKey: _endpointKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'System & Hardware Metrics',
          description:
              'Monitor on-device CPU load, RAM consumption, and available local storage in real time.',
          targetKey: _configKey,
          tooltipPosition: TooltipPosition.top,
        ),
        GuidedTourStep(
          title: 'Live Server Logs',
          description:
              'Watch real-time build and request logs here. Filter or copy them to debug your deployment.',
          targetKey: _logsKey,
          tooltipPosition: TooltipPosition.top,
        ),
      ];
      ref.read(guidedTourNotifierProvider.notifier).checkAndAutoStartTour(
            steps,
            tourKey: 'buildify_tour_project_detail',
          );
    });
  }

  @override
  void dispose() {
    _logSearchController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollLogsToBottom() {
    if (!_logScrollController.hasClients) return;
    _logScrollController.animateTo(
      _logScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } else {
      if (mounted) {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL copied (could not open browser): $url')),
        );
      }
    }
  }

  Future<void> _editSubdomain(BackendProject project) async {
    final controller = TextEditingController(text: project.subdomain);
    final service = ref.read(embeddedBackendProvider).liveUrls;
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, update) => AlertDialog(
                  backgroundColor: _DetailPalette.surfaceContainer,
                  shape: const RoundedRectangleBorder(
                    side: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                  title: Text(
                    'Edit Subdomain',
                    style: GoogleFonts.spaceMono(
                      color: _DetailPalette.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: TextField(
                    controller: controller,
                    enabled: !saving,
                    style: GoogleFonts.spaceMono(color: _DetailPalette.onSurface),
                    onChanged: (value) => update(() => error = validateSubdomain(value)),
                    decoration: InputDecoration(
                      suffixText: '.$baseDomain',
                      suffixStyle: GoogleFonts.spaceMono(color: _DetailPalette.onSurfaceVariant),
                      errorText: error,
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: _DetailPalette.outlineVariant),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: _DetailPalette.primary),
                      ),
                    ),
                  ),
                  actions: [
                    _OutlineButton(
                      label: 'CANCEL',
                      onTap: saving ? () {} : () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 8),
                    _PrimaryButton(
                      label: saving ? 'SAVING…' : 'SAVE',
                      icon: Icons.check,
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

  List<_LogLine> _allLogs(List<BackendLogEvent> backendLogs) {
    if (backendLogs.isEmpty) {
      final now = DateTime.now();
      final ts = _formatTime(now);
      return [
        _LogLine(ts, '[buildify]', 'runtime ready: project service configured', createdAt: now, highlight: true, success: true),
        _LogLine(ts, '[buildify]', 'listening for connections & build events', createdAt: now, dim: true),
      ];
    }

    return backendLogs.map((l) {
      final t = l.createdAt;
      final ts = _formatTime(t);
      final isErr = l.type == BackendLogType.error;
      final isSys = l.type == BackendLogType.system;
      return _LogLine(
        ts,
        '[buildify]',
        l.message,
        createdAt: t,
        highlight: isSys,
        warning: isErr,
        dim: !isSys && !isErr,
      );
    }).toList();
  }

  String _formatTime(DateTime t) {
    final h = t.hour >= 12
        ? (t.hour == 12 ? 12 : t.hour - 12)
        : (t.hour == 0 ? 12 : t.hour);
    return '$h:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'pm' : 'am'}';
  }

  List<_LogLine> _filteredLogs(List<_LogLine> logs) {
    var result = logs;
    if (_timeRange == 'last hour') {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      result = result.where((l) => l.createdAt.isAfter(cutoff)).toList();
    }
    final q = _logSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where((l) =>
              l.message.toLowerCase().contains(q) ||
              l.instance.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final backendNotifier = ref.read(embeddedBackendProvider);
    final backendState = ref.watch(backendStateProvider).value ?? backendNotifier.state;
    final aiState = ref.watch(aiServerProvider);
    final device = aiState.device;

    final project = backendState.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => BackendProject(
        id: widget.projectId,
        name: 'Project',
        repoProvider: 'GitHub',
        url: '',
        lastDeployedAt: null,
        isLive: false,
      ),
    );

    final activeSession = backendState.activeSession;
    final isRunning = project.isLive;

    // Log calculation & auto-scroll
    final backendLogs = backendState.logs.where((l) => l.projectId == project.id).toList();
    final logs = _filteredLogs(_allLogs(backendLogs));
    if (logs.length != _lastLogCount) {
      _lastLogCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollLogsToBottom());
    }

    final horizontalPadding = MediaQuery.sizeOf(context).width >= 768 ? 32.0 : 16.0;

    // Metrics calculations
    final ramUsed = (device.ramGb - device.availRamGb).clamp(0, device.ramGb.toDouble());
    final ramPct = device.ramGb > 0 ? (ramUsed / device.ramGb * 100).round() : 0;
    final storagePct = device.freeStorageGb > 0
        ? ((1 - device.freeStorageGb / (device.freeStorageGb + 8)) * 100).round().clamp(0, 100)
        : 0;
    final cpuPct = (aiState.requestsPerSecond * 8).clamp(0, 100).round();

    // Endpoints
    final apiUrl = 'http://${device.ipAddress}:${project.port}';
    final liveUrl = project.liveUrl.isNotEmpty
        ? project.liveUrl
        : (activeSession != null && activeSession.projectId == project.id
            ? activeSession.publicUrl
            : '${device.ipAddress}:${project.port}');
    final subdomainUrl = project.subdomain.isNotEmpty
        ? 'https://${project.subdomain}.$baseDomain'
        : 'https://${projectNameSubdomain(project.name)}.$baseDomain';
    final serviceId = 'web-${project.port}';
    final repoLabel = project.name;
    final terminalHeight = _logsFullscreen ? MediaQuery.sizeOf(context).height * 0.75 : 400.0;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _DetailPalette.background,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
          backgroundColor: _DetailPalette.background,
          body: DecoratedBox(
            decoration: const BoxDecoration(color: _DetailPalette.background),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: _MeshBackground()),
                SafeArea(
                  child: Column(
                    children: [
                      _DetailTopBar(
                        horizontalPadding: horizontalPadding,
                        onOpenSettings:
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => EnvManagementPage(
                                      projectId: project.id,
                                    ),
                              ),
                            ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: _DetailPalette.background,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              8,
                              horizontalPadding,
                              48,
                            ),
                            children: [
                              // 1. Breadcrumbs & Header
                              _ProjectHeaderIntro(
                                projectName: project.name,
                                repoProvider: project.repoProvider,
                                isRunning: isRunning,
                                port: project.port,
                                onManualDeploy: () async {
                                  if (project.isLive) {
                                    if (activeSession != null) {
                                      await backendNotifier.stopSession(sessionId: activeSession.id);
                                    }
                                  } else {
                                    await backendNotifier.startSession(projectId: project.id);
                                  }
                                },
                                controlKey: _controlKey,
                              ),
                              const SizedBox(height: 32),

                              // 2. Metadata Grid (service id, repository, live url / subdomain)
                              _MetadataGrid(
                                key: _endpointKey,
                                serviceId: serviceId,
                                repo: repoLabel,
                                liveUrl: liveUrl.replaceFirst(RegExp(r'^https?://'), ''),
                                subdomain: subdomainUrl,
                                subdomainStatus: project.liveUrlStatus,
                                onCopyId: () {
                                  Clipboard.setData(ClipboardData(text: apiUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('API URL copied')),
                                  );
                                },
                                onOpenUrl: () => _openUrl(subdomainUrl),
                                onEditSubdomain: () => _editSubdomain(project),
                              ),
                              const SizedBox(height: 48),

                              // 3. Environment Variables
                              _EnvVariablesSection(
                                envVars: project.envVars,
                                onManage: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder:
                                        (_) => EnvManagementPage(
                                          projectId: project.id,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 48),

                              // 4. System Status
                              _SystemStatusSection(
                                key: _configKey,
                                deviceLabel: device.cpuLabel.isNotEmpty ? device.cpuLabel : 'IQOO 9se',
                                batteryPercent: device.batteryPercent,
                                charging: device.batteryCharging,
                                cpuPct: cpuPct,
                                ramLabel: '${ramUsed.toStringAsFixed(1)}GB / ${device.ramGb}GB',
                                ramPct: ramPct,
                                storageLabel: '${device.freeStorageGb.toStringAsFixed(1)}GB free',
                                storagePct: storagePct,
                              ),
                              const SizedBox(height: 48),

                              // 5. Active Runtime Status
                              _ActiveRuntimeSection(
                                projectName: project.name,
                                isRunning: isRunning,
                                port: project.port,
                                repoProvider: project.repoProvider,
                              ),
                              const SizedBox(height: 48),

                              // 6. Runtime Logs Terminal
                              _RuntimeLogsSection(
                                key: _logsKey,
                                logs: logs,
                                logSearchController: _logSearchController,
                                logScrollController: _logScrollController,
                                terminalHeight: terminalHeight,
                                timeRange: _timeRange,
                                showCustomRange: _showCustomRange,
                                logsFullscreen: _logsFullscreen,
                                onSearchChanged: () => setState(() {}),
                                onToggleFullscreen: () => setState(() => _logsFullscreen = !_logsFullscreen),
                                onScrollToBottom: _scrollLogsToBottom,
                                onTimeRangeTap: () {
                                  setState(() {
                                    _showCustomRange = !_showCustomRange;
                                    if (!_showCustomRange) {
                                      _timeRange = 'last hour';
                                    }
                                  });
                                },
                                onApplyCustomRange: () {
                                  setState(() {
                                    _showCustomRange = false;
                                    _timeRange = 'custom range';
                                  });
                                },
                                onCancelCustomRange: () => setState(() => _showCustomRange = false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

// ==========================================
// MESH BACKGROUND
// ==========================================
class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _DetailPalette.background),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.4),
              radius: 1.2,
              colors: [
                Colors.white.withValues(alpha: 0.01),
                Colors.transparent,
              ],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.7),
                radius: 1.0,
                colors: [
                  Colors.white.withValues(alpha: 0.01),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TOP BAR
// ==========================================
class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.horizontalPadding,
    required this.onOpenSettings,
  });

  final double horizontalPadding;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: _DetailPalette.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _DetailPalette.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              shape: const RoundedRectangleBorder(
                side: BorderSide(color: Color(0x0DFFFFFF)),
              ),
            ),
            onPressed: () => Navigator.maybePop(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: _DetailPalette.onSurface,
                ),
                Text(
                  'back',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: _DetailPalette.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(
            Icons.architecture,
            color: _DetailPalette.primary,
            size: 28,
          ),
          const SizedBox(width: 8),
          Text(
            'buildify',
            style: GoogleFonts.spaceMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: _DetailPalette.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Project Settings',
            onPressed: onOpenSettings,
            icon: const Icon(
              Icons.settings_outlined,
              color: _DetailPalette.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// HEADER INTRO & BREADCRUMBS
// ==========================================
class _ProjectHeaderIntro extends StatelessWidget {
  const _ProjectHeaderIntro({
    required this.projectName,
    required this.repoProvider,
    required this.isRunning,
    required this.port,
    required this.onManualDeploy,
    required this.controlKey,
  });

  final String projectName;
  final String repoProvider;
  final bool isRunning;
  final int port;
  final VoidCallback onManualDeploy;
  final Key controlKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumbs
        Row(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 14,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            Icon(
              Icons.chevron_right,
              size: 12,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            Text(
              projectName.toLowerCase(),
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 12,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            Text(
              'local-server',
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _DetailPalette.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Service Header
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 640;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.language,
                      size: 16,
                      color: _DetailPalette.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'web application service',
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: _DetailPalette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  projectName,
                  style: GoogleFonts.spaceMono(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.48,
                    color: _DetailPalette.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _TagChip(repoProvider.toLowerCase()),
                    const _TagChip('on-device edge'),
                    _TagChip('port $port'),
                  ],
                ),
              ],
            );

            final actions = _PrimaryButton(
              key: controlKey,
              label: isRunning ? 'STOP SERVER' : 'START SERVER',
              icon: isRunning ? Icons.stop : Icons.play_arrow,
              onTap: onManualDeploy,
              backgroundColor:
                  isRunning
                      ? _DetailPalette.statusSuspended
                      : _DetailPalette.primary,
              foregroundColor: isRunning ? Colors.white : _DetailPalette.onPrimary,
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 24), actions],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [Expanded(child: title), actions],
            );
          },
        ),
      ],
    );
  }
}

// ==========================================
// METADATA GRID
// ==========================================
class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({
    super.key,
    required this.serviceId,
    required this.repo,
    required this.liveUrl,
    required this.onCopyId,
    required this.onOpenUrl,
    required this.subdomain,
    required this.subdomainStatus,
    required this.onEditSubdomain,
  });

  final String serviceId;
  final String repo;
  final String liveUrl;
  final VoidCallback onCopyId;
  final VoidCallback onOpenUrl;
  final String subdomain;
  final String subdomainStatus;
  final VoidCallback onEditSubdomain;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _DetailPalette.outlineVariant),
        color: _DetailPalette.surfaceContainerLowest,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 600;
          final cells = [
            _MetaCell(
              label: 'service id',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      serviceId,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onCopyId,
                    icon: const Icon(Icons.content_copy, size: 16),
                    color: _DetailPalette.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            _MetaCell(
              label: 'repository',
              child: Row(
                children: [
                  const Icon(
                    Icons.code,
                    size: 16,
                    color: _DetailPalette.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      repo,
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: _DetailPalette.outlineVariant),
                    ),
                    child: Text(
                      'main',
                      style: GoogleFonts.spaceMono(
                        fontSize: 8,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _MetaCell(
              label: 'live url',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          liveUrl,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceMono(
                            fontSize: 14,
                            color: _DetailPalette.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: _DetailPalette.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onOpenUrl,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        color: _DetailPalette.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'project subdomain · $subdomainStatus',
                    style: const TextStyle(fontSize: 10, color: _DetailPalette.onSurfaceVariant),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          subdomain,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _DetailPalette.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy subdomain',
                        icon: const Icon(Icons.content_copy, size: 16),
                        onPressed:
                            () => Clipboard.setData(
                              ClipboardData(text: subdomain),
                            ),
                      ),
                      IconButton(
                        tooltip: 'Edit subdomain',
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        onPressed: onEditSubdomain,
                      ),
                      IconButton(
                        tooltip: 'Open subdomain',
                        icon: const Icon(Icons.open_in_new, size: 16),
                        onPressed: onOpenUrl,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
          if (stacked) {
            return Column(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: _DetailPalette.outlineVariant),
                  cells[i],
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[0]),
                const VerticalDivider(width: 1, color: _DetailPalette.outlineVariant),
                Expanded(child: cells[1]),
                const VerticalDivider(width: 1, color: _DetailPalette.outlineVariant),
                Expanded(child: cells[2]),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ==========================================
// ENVIRONMENT VARIABLES SECTION
// ==========================================
class _EnvVariablesSection extends StatelessWidget {
  const _EnvVariablesSection({required this.envVars, required this.onManage});

  final Map<String, String> envVars;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final keys = envVars.keys.toList()..sort();
    const previewLimit = 8;
    final preview = keys.take(previewLimit).toList();
    final overflow = keys.length - preview.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('environment'),
            const Spacer(),
            _OutlineButton(
              label: 'MANAGE',
              trailing: Icons.arrow_forward,
              onTap: onManage,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(
              color: _DetailPalette.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow.withValues(
                    alpha: 0.5,
                  ),
                  border: const Border(
                    bottom: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.password_outlined,
                      size: 16,
                      color: _DetailPalette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'environment variables',
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${keys.length} configured',
                      style: GoogleFonts.spaceMono(
                        fontSize: 8,
                        letterSpacing: 0.8,
                        color: _DetailPalette.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child:
                    keys.isEmpty
                        ? InkWell(
                          onTap: onManage,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.add,
                                  size: 14,
                                  color: _DetailPalette.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'no variables configured — add secrets and config values for this project',
                                    style: GoogleFonts.spaceMono(
                                      fontSize: 10,
                                      height: 1.5,
                                      color: _DetailPalette.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final key in preview)
                              _EnvKeyChip(keyName: key),
                            if (overflow > 0)
                              Text(
                                '+$overflow more',
                                style: GoogleFonts.spaceMono(
                                  fontSize: 9,
                                  color: _DetailPalette.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EnvKeyChip extends StatelessWidget {
  const _EnvKeyChip({required this.keyName});

  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _DetailPalette.surfaceContainerLowest,
        border: Border.all(
          color: _DetailPalette.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyName,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _DetailPalette.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '••••••',
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              letterSpacing: 1,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SYSTEM STATUS SECTION
// ==========================================
class _SystemStatusSection extends StatelessWidget {
  const _SystemStatusSection({
    super.key,
    required this.deviceLabel,
    required this.batteryPercent,
    required this.charging,
    required this.cpuPct,
    required this.ramLabel,
    required this.ramPct,
    required this.storageLabel,
    required this.storagePct,
  });

  final String deviceLabel;
  final int batteryPercent;
  final bool charging;
  final int cpuPct;
  final String ramLabel;
  final int ramPct;
  final String storageLabel;
  final int storagePct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('system status'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(
              color: _DetailPalette.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow.withValues(
                    alpha: 0.5,
                  ),
                  border: const Border(
                    bottom: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.dns_outlined,
                      size: 16,
                      color: _DetailPalette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      deviceLabel.toLowerCase(),
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.bolt,
                      size: 14,
                      color: _DetailPalette.successGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$batteryPercent% ${charging ? 'charging' : ''}'.trim(),
                      style: GoogleFonts.spaceMono(
                        fontSize: 8,
                        letterSpacing: 0.8,
                        color: _DetailPalette.successGreen,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 600;
                    final bars = [
                      _ProgressMetric(
                        label: 'cpu usage',
                        value: '$cpuPct%',
                        pct: cpuPct,
                      ),
                      _ProgressMetric(
                        label: 'ram consumption',
                        value: ramLabel,
                        pct: ramPct,
                      ),
                      _ProgressMetric(
                        label: 'storage',
                        value: storageLabel,
                        pct: storagePct,
                      ),
                    ];
                    if (stacked) {
                      return Column(
                        children: [
                          for (var i = 0; i < bars.length; i++) ...[
                            if (i > 0) const SizedBox(height: 32),
                            bars[i],
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: bars[0]),
                        const SizedBox(width: 32),
                        Expanded(child: bars[1]),
                        const SizedBox(width: 32),
                        Expanded(child: bars[2]),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.label,
    required this.value,
    required this.pct,
  });

  final String label;
  final String value;
  final int pct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceMono(
                fontSize: 8,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _DetailPalette.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            color: _DetailPalette.primary,
          ),
        ),
      ],
    );
  }
}

// ==========================================
// ACTIVE RUNTIME STATUS SECTION
// ==========================================
class _ActiveRuntimeSection extends StatelessWidget {
  const _ActiveRuntimeSection({
    required this.projectName,
    required this.isRunning,
    required this.port,
    required this.repoProvider,
  });

  final String projectName;
  final bool isRunning;
  final int port;
  final String repoProvider;

  @override
  Widget build(BuildContext context) {
    final statusLabel = isRunning ? 'online' : 'offline';
    final statusColor = isRunning ? _DetailPalette.successGreen : _DetailPalette.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('active runtime status'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(color: _DetailPalette.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    _PulseStatusIndicator(
                      color: statusColor,
                      pulse: isRunning,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        statusLabel.toUpperCase(),
                        style: GoogleFonts.spaceMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _DetailPalette.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      color: statusColor.withValues(alpha: 0.2),
                      child: Text(
                        isRunning ? 'LIVE' : 'STOPPED',
                        style: GoogleFonts.spaceMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                color: _DetailPalette.surfaceContainerLow,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _DetailPalette.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'PORT $port',
                        style: GoogleFonts.spaceMono(
                          fontSize: 8,
                          color: _DetailPalette.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'service: ${projectName.toLowerCase()} — $repoProvider runtime',
                        style: GoogleFonts.spaceMono(
                          fontSize: 14,
                          color: _DetailPalette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// RUNTIME LOGS SECTION
// ==========================================
class _RuntimeLogsSection extends StatelessWidget {
  const _RuntimeLogsSection({
    super.key,
    required this.logs,
    required this.logSearchController,
    required this.logScrollController,
    required this.terminalHeight,
    required this.timeRange,
    required this.showCustomRange,
    required this.logsFullscreen,
    required this.onSearchChanged,
    required this.onToggleFullscreen,
    required this.onScrollToBottom,
    required this.onTimeRangeTap,
    required this.onApplyCustomRange,
    required this.onCancelCustomRange,
  });

  final List<_LogLine> logs;
  final TextEditingController logSearchController;
  final ScrollController logScrollController;
  final double terminalHeight;
  final String timeRange;
  final bool showCustomRange;
  final bool logsFullscreen;
  final VoidCallback onSearchChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onScrollToBottom;
  final VoidCallback onTimeRangeTap;
  final VoidCallback onApplyCustomRange;
  final VoidCallback onCancelCustomRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionLabel('runtime logs')),
            IconButton(
              tooltip: 'Copy logs',
              onPressed: () {
                if (logs.isEmpty) return;
                final text = logs
                    .map((l) => '${l.time} ${l.instance} ${l.message}')
                    .join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            IconButton(
              onPressed: onToggleFullscreen,
              icon: Icon(
                logsFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
              ),
              style:
                  logsFullscreen
                      ? IconButton.styleFrom(
                        backgroundColor: _DetailPalette.primary,
                        foregroundColor: _DetailPalette.onPrimary,
                      )
                      : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(color: _DetailPalette.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 600;
                    final filters = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _OutlineButton(
                          label: timeRange,
                          trailing: Icons.expand_more,
                          onTap: onTimeRangeTap,
                          icon: Icons.schedule,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _DetailPalette.primary.withValues(
                              alpha: 0.1,
                            ),
                            border: Border.all(color: _DetailPalette.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt,
                                size: 14,
                                color: _DetailPalette.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'live tail',
                                style: GoogleFonts.spaceMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _DetailPalette.primary,
                                ),
                              ),
                              const Icon(
                                Icons.expand_more,
                                size: 14,
                                color: _DetailPalette.primary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final search = TextField(
                      controller: logSearchController,
                      onChanged: (_) => onSearchChanged(),
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'search logs...',
                        hintStyle: GoogleFonts.spaceMono(
                          fontSize: 14,
                          color: _DetailPalette.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: _DetailPalette.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _DetailPalette.outlineVariant,
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _DetailPalette.primary),
                        ),
                      ),
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [filters, const SizedBox(height: 12), search],
                      );
                    }
                    return Row(
                      children: [
                        filters,
                        const SizedBox(width: 16),
                        Expanded(child: search),
                      ],
                    );
                  },
                ),
              ),
              if (showCustomRange)
                _CustomRangePicker(
                  onCancel: onCancelCustomRange,
                  onApply: onApplyCustomRange,
                ),
              Stack(
                children: [
                  SizedBox(
                    height: terminalHeight,
                    child: ColoredBox(
                      color: _DetailPalette.terminalBg,
                      child: Scrollbar(
                        controller: logScrollController,
                        thumbVisibility: true,
                        child: ListView(
                          controller: logScrollController,
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              _todayHeader(),
                              style: GoogleFonts.spaceMono(
                                fontSize: 14,
                                color: _DetailPalette.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...logs.map((l) => _LogLineWidget(line: l)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: Material(
                      color: _DetailPalette.primary,
                      child: InkWell(
                        onTap: onScrollToBottom,
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.arrow_downward,
                            color: _DetailPalette.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// CUSTOM RANGE PICKER
// ==========================================
class _CustomRangePicker extends StatelessWidget {
  const _CustomRangePicker({required this.onCancel, required this.onApply});

  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final offsetStr = now.timeZoneOffset.isNegative ? '-' : '+';
    final offsetHours = now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes = (now.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final tzLabel = 'GMT$offsetStr$offsetHours:$offsetMinutes';

    return Container(
      padding: const EdgeInsets.all(24),
      color: _DetailPalette.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Custom Range Selection',
                style: GoogleFonts.spaceMono(
                  fontSize: 8,
                  letterSpacing: 1.6,
                  color: _DetailPalette.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _RangeField(
            label: 'START ($tzLabel)',
            date: '${_monthName(oneHourAgo)} ${oneHourAgo.day} ${oneHourAgo.year}',
            time: '${oneHourAgo.hour.toString().padLeft(2, '0')}:${oneHourAgo.minute.toString().padLeft(2, '0')}:${oneHourAgo.second.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 16),
          _RangeField(
            label: 'END ($tzLabel)',
            date: '${_monthName(now)} ${now.day} ${now.year}',
            time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _OutlineButton(label: 'cancel', onTap: onCancel),
              const SizedBox(width: 12),
              _PrimaryButton(
                label: 'apply custom range',
                icon: Icons.check,
                onTap: onApply,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _monthName(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[dt.month - 1];
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.date,
    required this.time,
  });

  final String label;
  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 8,
            color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: _DetailPalette.outlineVariant),
                  color: _DetailPalette.surfaceContainerLowest,
                ),
                child: Text(date, style: GoogleFonts.spaceMono(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _DetailPalette.outlineVariant),
                color: _DetailPalette.surfaceContainerLowest,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 18,
                    color: _DetailPalette.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(time, style: GoogleFonts.spaceMono(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==========================================
// REUSABLE CHIPS & BUTTONS
// ==========================================
class _TagChip extends StatelessWidget {
  const _TagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: _DetailPalette.surfaceContainerLow,
        border: Border.all(color: _DetailPalette.outlineVariant),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: _DetailPalette.onSurface,
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.trailing,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _DetailPalette.background,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: _DetailPalette.onSurface),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _DetailPalette.onSurface,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, size: 16, color: _DetailPalette.onSurface),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? _DetailPalette.primary;
    final fg = foregroundColor ?? _DetailPalette.onPrimary;
    final disabled = onTap == null;

    return Material(
      color: disabled ? bg.withValues(alpha: 0.5) : bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: fg,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _PulseStatusIndicator extends StatefulWidget {
  const _PulseStatusIndicator({required this.color, this.pulse = false});
  final Color color;
  final bool pulse;

  @override
  State<_PulseStatusIndicator> createState() => _PulseStatusIndicatorState();
}

class _PulseStatusIndicatorState extends State<_PulseStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.pulse) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _PulseStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !oldWidget.pulse) {
      _controller.repeat();
    } else if (!widget.pulse && oldWidget.pulse) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 1.0 + _controller.value * 1.5,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(
                    alpha: (1.0 - _controller.value) * 0.4,
                  ),
                ),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogLineWidget extends StatelessWidget {
  const _LogLineWidget({required this.line});

  final _LogLine line;

  @override
  Widget build(BuildContext context) {
    Color messageColor = _DetailPalette.onSurface;
    if (line.highlight) {
      messageColor = _DetailPalette.primary;
    }
    if (line.success) {
      messageColor = _DetailPalette.successGreen;
    }
    if (line.warning) {
      messageColor = _DetailPalette.statusSuspended;
    }
    if (line.dim) {
      messageColor = _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6);
    }

    Widget messageChild = Text(
      line.message,
      style: GoogleFonts.spaceMono(fontSize: 14, color: messageColor),
    );
    if (line.success) {
      messageChild = Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: _DetailPalette.successGreen,
          ),
          const SizedBox(width: 8),
          Expanded(child: messageChild),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              line.time,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              line.instance,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(child: messageChild),
        ],
      ),
    );
  }
}

String _todayHeader() {
  final now = DateTime.now();
  final months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  return '${months[now.month - 1]} ${now.day}, ${now.year}';
}
