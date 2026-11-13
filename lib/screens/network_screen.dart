import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palette.dart';
import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';

class NetworkScreen extends ConsumerWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiServerProvider);
    final controller = ref.read(aiServerProvider.notifier);
    final baseUrl = controller.apiBaseUrl;
    final tunnel = state.tunnel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionTitle('Network'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Local IP', value: state.device.ipAddress),
                _InfoRow(label: 'Port', value: '${state.port}'),
                _InfoRow(label: 'Status', value: _statusLabel(state.status)),
                _InfoRow(
                  label: 'Auth',
                  value:
                      state.security.requireApiKey
                          ? 'API key required'
                          : 'Open (no key)',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppPalette.border),
                  ),
                  child: SelectableText(
                    baseUrl,
                    style: const TextStyle(
                      color: AppPalette.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _copyApiUrl(context, baseUrl),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy API URL'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Cloudflare Tunnel'),
        SwitchListTile(
          title: const Text('Allow public AI sharing'),
          subtitle: const Text(
            'Requires an API key. Restart the model after changing authentication before publishing.',
          ),
          value: controller.modelAccessScope == ModelAccessScope.public,
          onChanged: (enabled) async {
            try {
              if (enabled) {
                if (state.security.apiKey.isEmpty) {
                  await controller.regenerateApiKey();
                }
                await controller.setRequireApiKey(true);
              }
              await controller.setModelAccessScope(
                enabled
                    ? ModelAccessScope.public
                    : ModelAccessScope.deviceNetwork,
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sharing settings could not be saved.'),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TunnelDot(status: tunnel.status),
                    const SizedBox(width: 8),
                    Text(
                      _tunnelStatusLabel(tunnel.status),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (tunnel.publicUrl != null) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Public URL',
                    style: TextStyle(color: AppPalette.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.border),
                    ),
                    child: SelectableText(
                      tunnel.publicUrl!,
                      style: const TextStyle(
                        color: AppPalette.primary,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      if (tunnel.publicUrl != null) {
                        unawaited(
                          Clipboard.setData(
                            ClipboardData(text: tunnel.publicUrl!),
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tunnel URL copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Tunnel URL'),
                  ),
                ],
                if (tunnel.lastError != null &&
                    tunnel.status == TunnelStatus.failed) ...[
                  const SizedBox(height: 8),
                  Text(
                    tunnel.lastError!,
                    style: const TextStyle(
                      color: AppPalette.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            tunnel.status == TunnelStatus.running ||
                                    tunnel.status == TunnelStatus.starting
                                ? null
                                : () async {
                                  final ok = await controller.startTunnel();
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enable public sharing and restart with API-key protection before publishing.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        icon: Icon(
                          tunnel.status == TunnelStatus.running
                              ? Icons.cloud_done
                              : Icons.cloud_outlined,
                        ),
                        label: Text(
                          tunnel.status == TunnelStatus.starting
                              ? 'Starting...'
                              : (tunnel.status == TunnelStatus.running
                                  ? 'Tunnel Active'
                                  : 'Start Tunnel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (tunnel.status == TunnelStatus.running ||
                        tunnel.status == TunnelStatus.starting)
                      IconButton.filledTonal(
                        tooltip: 'Stop tunnel',
                        onPressed:
                            tunnel.status == TunnelStatus.running
                                ? () => unawaited(controller.stopTunnel())
                                : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Creates a public HTTPS URL via Cloudflare. No account needed — uses trycloudflare.com quick tunnels.',
                  style: TextStyle(color: AppPalette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Tailscale VPN'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.device.tailscaleIp != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppPalette.teal,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tailscale connected',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'Tailscale IP',
                    value: state.device.tailscaleIp!,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.border),
                    ),
                    child: SelectableText(
                      'http://${state.device.tailscaleIp}:${state.port}',
                      style: const TextStyle(
                        color: AppPalette.blue,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final url =
                          'http://${state.device.tailscaleIp}:${state.port}';
                      unawaited(Clipboard.setData(ClipboardData(text: url)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tailscale URL copied')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Tailscale URL'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.vpn_lock,
                        color: AppPalette.muted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Not connected',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tailscale gives each device a private 100.x.x.x IP so devices on your tailnet '
                    'can reach the AI server without exposing it publicly.',
                    style: TextStyle(color: AppPalette.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'How to set up:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '1. Install Tailscale from Play Store\n'
                    '2. Sign up / log in\n'
                    '3. Tap the toggle to connect\n'
                    '4. Come back here — your Tailscale IP will appear automatically\n'
                    '5. On your laptop, install Tailscale and log in with the same account\n'
                    '6. Use the Tailscale URL above from your laptop',
                    style: TextStyle(
                      color: AppPalette.muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Endpoints'),
        const SizedBox(height: 8),
        const _EndpointTile(method: 'GET', path: '/health'),
        const SizedBox(height: 8),
        const _EndpointTile(method: 'POST', path: '/completion'),
        const SizedBox(height: 8),
        const _EndpointTile(method: 'POST', path: '/chat'),
        const SizedBox(height: 18),
        const _SectionTitle('Example Body'),
        const SizedBox(height: 8),
        const _CodeBlock(
          text:
              '{\n'
              '  "prompt": "Explain quantum physics simply",\n'
              '  "n_predict": 100,\n'
              '  "temperature": 0.7\n'
              '}',
        ),
      ],
    );
  }
}

class _TunnelDot extends StatelessWidget {
  const _TunnelDot({required this.status});

  final TunnelStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TunnelStatus.running => AppPalette.teal,
      TunnelStatus.starting => AppPalette.amber,
      TunnelStatus.failed => AppPalette.error,
      TunnelStatus.stopped => AppPalette.muted,
    };
    return Container(
      height: 12,
      width: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

String _tunnelStatusLabel(TunnelStatus status) {
  return switch (status) {
    TunnelStatus.stopped => 'Tunnel Off',
    TunnelStatus.starting => 'Connecting...',
    TunnelStatus.running => 'Tunnel Active',
    TunnelStatus.failed => 'Tunnel Failed',
  };
}

class _EndpointTile extends StatelessWidget {
  const _EndpointTile({required this.method, required this.path});

  final String method;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: method == 'GET' ? AppPalette.blue : AppPalette.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            method,
            style: const TextStyle(
              color: AppPalette.bg,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(path, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          color: AppPalette.text,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(color: AppPalette.muted)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppPalette.text,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

String _statusLabel(ServerStatus status) {
  return switch (status) {
    ServerStatus.stopped => 'stopped',
    ServerStatus.starting => 'starting',
    ServerStatus.running => 'running',
    ServerStatus.stopping => 'stopping',
  };
}

void _copyApiUrl(BuildContext context, String baseUrl) {
  unawaited(Clipboard.setData(ClipboardData(text: baseUrl)));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('API URL copied')));
}
