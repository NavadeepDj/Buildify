import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/embedded_backend.dart';
import '../providers/ai_server_provider.dart';
import '../services/native_server_bridge.dart';

class ProjectDetailPage extends ConsumerStatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends ConsumerState<ProjectDetailPage> {
  final _logSearchController = TextEditingController();
  final _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _logSearchController.addListener(() => setState(() {}));
    _loadLocalIp();
  }

  String _localIp = '127.0.0.1';

  Future<void> _loadLocalIp() async {
    try {
      final ip = await const NativeServerBridge().getLocalIp();
      if (ip != null && ip.isNotEmpty && mounted) {
        setState(() => _localIp = ip);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _logSearchController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  bool _isCheckingReachability = false;

  Future<bool> _isServerReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      final socket = await Socket.connect(
        uri.host,
        uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openUrl(String url, {bool checkReachability = false}) async {
    if (checkReachability) {
      if (_isCheckingReachability) return;
      setState(() => _isCheckingReachability = true);
      try {
        final reachable = await _isServerReachable(url);
        if (!reachable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Server not reachable. Make sure the server is running.',
                        style: GoogleFonts.spaceMono(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.redAccent.shade700,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
          return;
        }
      } finally {
        if (mounted) setState(() => _isCheckingReachability = false);
      }
    }

    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendNotifier = ref.read(embeddedBackendProvider);
    final backendState = ref.watch(backendStateProvider).value ?? backendNotifier.state;

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
    final isSessionActive = activeSession != null && activeSession.projectId == project.id;
    final localUrl = 'http://$_localIp:${project.port}';
    final tunnelUrl = isSessionActive ? activeSession.publicUrl : null;
    // Only show as tunnel URL if it's a real Cloudflare tunnel (trycloudflare.com), not a placeholder
    final bool hasTunnelUrl = tunnelUrl != null &&
        tunnelUrl.isNotEmpty &&
        !tunnelUrl.contains('localhost') &&
        !tunnelUrl.contains('buildify.app') &&
        tunnelUrl != localUrl;

    final logs = backendState.logs.where((l) => l.projectId == project.id).toList();
    final filteredLogs = logs.where((l) {
      final q = _logSearchController.text.trim().toLowerCase();
      if (q.isEmpty) return true;
      return l.message.toLowerCase().contains(q);
    }).toList();

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF131312),
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F1F1E),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Text(
                project.name,
                style: GoogleFonts.spaceMono(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: project.isLive ? const Color(0xFF065F46) : const Color(0xFF374151),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  project.isLive ? 'ONLINE' : 'OFFLINE',
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete Project',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1F1F1E),
                    title: Text('Delete ${project.name}?', style: GoogleFonts.spaceMono(color: Colors.white)),
                    content: Text(
                      'Are you sure you want to permanently delete this project?',
                      style: GoogleFonts.spaceMono(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel', style: GoogleFonts.spaceMono(color: Colors.white54)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Delete', style: GoogleFonts.spaceMono(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await backendNotifier.deleteProject(project.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // 1. Live Control Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF20201F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: project.isLive ? Colors.green.withValues(alpha: 0.3) : Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            project.isLive ? Icons.check_circle : Icons.offline_bolt_outlined,
                            color: project.isLive ? const Color(0xFF10B981) : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Hosting Status',
                            style: GoogleFonts.spaceMono(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: project.isLive ? Colors.redAccent : Colors.white,
                          foregroundColor: project.isLive ? Colors.white : Colors.black,
                        ),
                        onPressed: () async {
                          if (project.isLive) {
                            if (activeSession != null) {
                              await backendNotifier.stopSession(sessionId: activeSession.id);
                            }
                          } else {
                            await backendNotifier.startSession(projectId: project.id);
                          }
                        },
                        icon: Icon(project.isLive ? Icons.stop : Icons.play_arrow, size: 18),
                        label: Text(
                          project.isLive ? 'Stop Server' : 'Start Server',
                          style: GoogleFonts.spaceMono(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),

                  // === LOCAL LAN LINK ===
                  Text(
                    'LOCAL NETWORK LINK',
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      color: Colors.white38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: project.isLive ? const Color(0xFF34D399).withValues(alpha: 0.3) : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lan_outlined,
                          size: 16,
                          color: project.isLive ? const Color(0xFF34D399) : Colors.white30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            localUrl,
                            style: GoogleFonts.spaceMono(
                              fontSize: 13,
                              color: project.isLive ? const Color(0xFF34D399) : Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                          tooltip: 'Copy Local URL',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: localUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Local URL copied to clipboard!')),
                            );
                          },
                        ),
                        if (project.isLive)
                          _isCheckingReachability
                              ? const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF34D399)),
                                  tooltip: 'Open in Browser',
                                  onPressed: () => _openUrl(localUrl, checkReachability: true),
                                ),
                      ],
                    ),
                  ),
                  if (!project.isLive)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 13, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Start the server to access this link. Make sure your device is on the same network.',
                              style: GoogleFonts.spaceMono(
                                fontSize: 10,
                                color: Colors.amber.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // === CLOUDFLARE TUNNEL LINK ===
                  Text(
                    'CLOUDFLARE TUNNEL LINK',
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      color: Colors.white38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasTunnelUrl ? const Color(0xFF60A5FA).withValues(alpha: 0.3) : Colors.white12,
                      ),
                    ),
                    child: hasTunnelUrl
                        ? Row(
                            children: [
                              const Icon(
                                Icons.cloud_outlined,
                                size: 16,
                                color: Color(0xFF60A5FA),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  tunnelUrl,
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 13,
                                    color: const Color(0xFF60A5FA),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                                tooltip: 'Copy Cloudflare URL',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: tunnelUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Cloudflare URL copied to clipboard!')),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF60A5FA)),
                                tooltip: 'Open in Browser',
                                onPressed: () => _openUrl(tunnelUrl),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  project.isLive
                                      ? (activeSession?.tunnelError != null
                                          ? 'Tunnel Error: ${activeSession!.tunnelError}'
                                          : 'Waiting for Cloudflare tunnel...')
                                      : 'Start the server to generate a Cloudflare link',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 12,
                                    color: (project.isLive && activeSession?.tunnelError != null)
                                        ? Colors.redAccent
                                        : Colors.white30,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              if (project.isLive && activeSession?.tunnelError == null)
                                const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF60A5FA),
                                    ),
                                  ),
                                ),
                              if (project.isLive && activeSession?.tunnelError != null)
                                const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (hasTunnelUrl)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.public, size: 13, color: Color(0xFF60A5FA)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'This link is accessible from anywhere on the internet.',
                              style: GoogleFonts.spaceMono(
                                fontSize: 10,
                                color: const Color(0xFF60A5FA).withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Configuration Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF20201F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuration & Ports',
                    style: GoogleFonts.spaceMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _configRow('Provider / Source', project.repoProvider),
                  _configRow('Branch', project.branch),
                  _configRow('Assigned Local Port', '${project.port}'),
                  _configRow('Local Folder', project.localPath),
                  if (project.buildCommand.isNotEmpty)
                    _configRow('Build Command', project.buildCommand),
                  if (project.publishDir.isNotEmpty)
                    _configRow('Publish Directory', project.publishDir),
                  if (project.envVars.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'ENVIRONMENT VARIABLES',
                      style: GoogleFonts.spaceMono(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...project.envVars.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${e.key} = ${e.value}',
                            style: GoogleFonts.spaceMono(fontSize: 12, color: Colors.white70),
                          ),
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3. System Logs Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF20201F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Console & Server Logs',
                          style: GoogleFonts.spaceMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                        tooltip: 'Copy Logs',
                        onPressed: () {
                          if (filteredLogs.isEmpty) return;
                          final allLogs = filteredLogs.map((l) => '[${l.type.name}] ${l.message}').join('\n');
                          Clipboard.setData(ClipboardData(text: allLogs));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Logs copied to clipboard!')),
                          );
                        },
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _logSearchController,
                          style: GoogleFonts.spaceMono(fontSize: 11, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Filter logs...',
                            hintStyle: GoogleFonts.spaceMono(fontSize: 11, color: Colors.white30),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            fillColor: Colors.black26,
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 240,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: filteredLogs.isEmpty
                        ? Center(
                            child: Text(
                              'No logs recorded yet.',
                              style: GoogleFonts.spaceMono(color: Colors.white30, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            controller: _logScrollController,
                            itemCount: filteredLogs.length,
                            itemBuilder: (context, index) {
                              final l = filteredLogs[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '[${l.createdAt.hour}:${l.createdAt.minute}:${l.createdAt.second}] ${l.message}',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 11,
                                    color: l.type == BackendLogType.error
                                        ? Colors.redAccent
                                        : (l.type == BackendLogType.system ? Colors.amberAccent : Colors.greenAccent),
                                  ),
                                ),
                              );
                            },
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

  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.spaceMono(fontSize: 12, color: Colors.white38),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: GoogleFonts.spaceMono(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
