import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant/status_probe_provider.dart';
import '../assistant/voice_bridge_session.dart';
import '../services/android_voice_tunnel.dart';
import '../services/voice_call_invitation.dart';
import 'voice_actions_screen.dart';
import 'embedded_voice_call_screen.dart';

/// Pairing credentials remain in this app session and are copied only on request.
class AndroidVoiceScreen extends ConsumerStatefulWidget {
  const AndroidVoiceScreen({super.key});

  @override
  ConsumerState<AndroidVoiceScreen> createState() => _AndroidVoiceScreenState();
}

class _AndroidVoiceScreenState extends ConsumerState<AndroidVoiceScreen> {
  final _phoneLink = TextEditingController();
  final _laptopLink = TextEditingController();
  VoiceRunTarget _target = VoiceRunTarget.phone;
  TextEditingController get _callLink =>
      _target == VoiceRunTarget.phone ? _phoneLink : _laptopLink;
  final _tunnel = const AndroidVoiceTunnel();
  Timer? _poll;
  String? _publicUrl;
  String? _message;
  String? _connectionMessage;
  bool _refreshing = false;
  bool _checkingCall = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phoneLink.dispose();
    _laptopLink.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _busy || _refreshing || _target != VoiceRunTarget.phone) {
      return;
    }
    final session = ref.read(voiceBridgeSessionProvider);
    if (session == null) return;
    _refreshing = true;
    try {
      final status = await _tunnel.status();
      if (!mounted ||
          _busy ||
          ref.read(voiceBridgeSessionProvider) != session) {
        return;
      }
      final url =
          status['status'] == 'running' ? status['publicUrl'] as String? : null;
      final message =
          status['status'] == 'failed'
              ? 'Voice connection failed. Disconnect and reconnect.'
              : url == null
              ? 'Connecting securely...'
              : 'Ready to pair with Bolna.';
      if (_publicUrl != url || _connectionMessage != message) {
        setState(() {
          _publicUrl = url;
          _connectionMessage = message;
        });
      }
    } catch (_) {
      if (mounted &&
          !_busy &&
          ref.read(voiceBridgeSessionProvider) == session) {
        setState(
          () => _connectionMessage = 'Could not check the voice connection.',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _enable() async {
    final sessionController = ref.read(voiceBridgeSessionProvider.notifier);
    setState(() {
      _busy = true;
      _message = 'Starting voice connection…';
    });
    try {
      sessionController.enable();
      final server = await ref.read(statusProbeProvider.future);
      if (server == null) throw StateError('Voice bridge unavailable');
      final result = await _tunnel.start();
      if (result['ok'] != true) throw StateError('Voice tunnel unavailable');
    } catch (_) {
      try {
        await _tunnel.stop();
      } catch (_) {
        // Revoke the bridge even when the native tunnel cannot be stopped.
      } finally {
        await sessionController.disable();
      }
      if (mounted) {
        setState(() {
          _connectionMessage = null;
          _message = 'Could not start voice. Try connecting again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  Future<void> _disable() async {
    final sessionController = ref.read(voiceBridgeSessionProvider.notifier);
    setState(() => _busy = true);
    try {
      try {
        final result = await _tunnel.stop();
        if (result['ok'] == false) throw StateError('Voice tunnel stop failed');
      } finally {
        await sessionController.disable();
      }
      if (mounted) {
        setState(() {
          _publicUrl = null;
          _connectionMessage = null;
          _message = 'Voice disconnected. Pair again after reconnecting.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _publicUrl = null;
          _connectionMessage = null;
          _message =
              'Voice pairing revoked. Close Buildify if the connection notification remains.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPairing() async {
    final session = ref.read(voiceBridgeSessionProvider);
    if (session == null || _publicUrl == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode({
          'platform': 'android',
          'public_url': '$_publicUrl/v1/status',
          'token': session.token,
        }),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pairing details copied. Share only with your own Buildify setup.',
          ),
        ),
      );
    }
  }

  Future<void> _call() async {
    setState(() {
      _busy = true;
      _checkingCall = true;
      _message = null;
    });
    final target = _target;
    try {
      final uri = VoiceCallInvitation.parse(_callLink.text);
      await VoiceCallInvitation.verify(uri, target);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/voice-call'),
          builder:
              (_) => EmbeddedVoiceCallScreen(invitation: uri, target: target),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message =
                  'Could not verify or open the call. Check your connection and run voice setup again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _checkingCall = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(voiceBridgeSessionProvider) != null;
    final onPhone = _target == VoiceRunTarget.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('Call Buildify')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Where should Buildify run?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<VoiceRunTarget>(
            segments: const [
              ButtonSegment(
                value: VoiceRunTarget.phone,
                label: Text('This phone'),
                icon: Icon(Icons.smartphone),
              ),
              ButtonSegment(
                value: VoiceRunTarget.laptop,
                label: Text('My laptop'),
                icon: Icon(Icons.laptop),
              ),
            ],
            selected: {_target},
            onSelectionChanged:
                _busy
                    ? null
                    : (value) => setState(() {
                      _target = value.single;
                      _message = null;
                      if (_target == VoiceRunTarget.phone) {
                        unawaited(_refresh());
                      }
                    }),
          ),
          const SizedBox(height: 16),
          Text(
            onPhone
                ? 'Run compatible AI models and host supported projects on this Android phone. Buildify checks available memory and storage on this phone before preparing a model.'
                : 'Use the microphone on your phone to manage Buildify on your paired laptop. Models and projects run on the laptop.',
          ),
          const SizedBox(height: 12),
          Text(
            onPhone
                ? 'Voice calls need your Bolna account and a trusted helper computer online. Phone hosting supports static sites; Node.js, Python and npm builds need the laptop. Review project changes here.'
                : 'Keep Buildify and the voice helper running on your laptop. Review project changes there. Phone hosting does not need to be enabled.',
          ),
          const SizedBox(height: 16),
          if (onPhone)
            FilledButton.icon(
              onPressed:
                  _busy
                      ? null
                      : enabled
                      ? _disable
                      : _enable,
              icon: Icon(enabled ? Icons.link_off : Icons.link),
              label: Text(
                enabled ? 'Disconnect voice' : 'Enable voice connection',
              ),
            ),
          if (onPhone && _connectionMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _connectionMessage!,
                semanticsLabel: _connectionMessage,
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!),
            ),
          if (onPhone && enabled) ...[
            const Text(
              '1. Copy pairing details to your trusted Buildify computer. Run the Android voice setup there using your Bolna account.',
            ),
            OutlinedButton.icon(
              onPressed: _publicUrl == null ? null : _copyPairing,
              icon: const Icon(Icons.copy),
              label: const Text('Copy pairing details'),
            ),
          ],
          if (!onPhone) ...[
            const Text(
              'Run laptop voice setup on your computer, then paste its private phone call link below.',
            ),
          ],
          if (!onPhone || enabled) ...[
            const SizedBox(height: 16),
            Text(
              onPhone
                  ? 'Paste the phone-mode call link returned by setup. The model runs here; the voice helper computer stays online.'
                  : 'Paste the laptop-mode call link. This call controls your laptop.',
            ),
            TextField(
              key: ValueKey(_target),
              controller: _callLink,
              decoration: InputDecoration(
                labelText: onPhone ? 'Phone call link' : 'Laptop call link',
              ),
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _busy || (onPhone && _publicUrl == null) ? null : _call,
              icon: const Icon(Icons.call),
              label: Text(
                _checkingCall
                    ? 'Checking call link...'
                    : onPhone
                    ? 'Call to control this phone'
                    : 'Call to control my laptop',
              ),
            ),
            const SizedBox(height: 12),
            if (onPhone)
              OutlinedButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/voice-actions'),
                        builder: (_) => const VoiceActionsScreen(),
                      ),
                    ),
                child: const Text('Review voice requests'),
              ),
            const SizedBox(height: 16),
            Text(
              onPhone
                  ? 'Allow microphone access in Buildify. Calls stay inside the app, with voice requests available for review. Reconnecting creates new pairing details. Bolna processes your voice online.'
                  : 'Allow microphone access in Buildify. Calls stay inside the app. The assistant will identify the laptop before handling requests. Bolna processes your voice online.',
            ),
          ],
        ],
      ),
    );
  }
}
