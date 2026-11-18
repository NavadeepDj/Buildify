import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/voice_call_invitation.dart';
import 'voice_actions_screen.dart';

/// The native view owns WebView media permissions and never receives a Bolna key.
class EmbeddedVoiceCallScreen extends StatefulWidget {
  const EmbeddedVoiceCallScreen({
    super.key,
    required this.invitation,
    required this.target,
  });

  final Uri invitation;
  final VoiceRunTarget target;

  @override
  State<EmbeddedVoiceCallScreen> createState() =>
      _EmbeddedVoiceCallScreenState();
}

class _EmbeddedVoiceCallScreenState extends State<EmbeddedVoiceCallScreen>
    with WidgetsBindingObserver {
  MethodChannel? _call;
  String? _message;
  bool _loading = true;
  bool _ready = false;
  bool _ended = false;
  int _attempt = 0;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final attempt = ++_attempt;
    setState(() {
      _loading = true;
      _ready = false;
      _ended = false;
      _message = 'Allow microphone access to talk to Buildify.';
    });
    try {
      final granted = await const MethodChannel(
        'buildify.ai/voice-microphone',
      ).invokeMethod<bool>('request');
      if (!mounted || attempt != _attempt) return;
      if (granted != true) {
        _finish(
          'Microphone access is needed. Allow it in Android app settings, then retry.',
        );
        return;
      }
      await VoiceCallInvitation.verify(widget.invitation, widget.target);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _ready = true;
        _message = 'Loading the secure call screen…';
      });
      _timeout = Timer(const Duration(seconds: 30), () {
        if (mounted && _loading) {
          _finish(
            'The call screen did not load. Check your connection and retry.',
          );
        }
      });
    } catch (_) {
      if (mounted && attempt == _attempt) {
        _finish(
          'Could not open the call. Check the selected device and run voice setup again.',
        );
      }
    }
  }

  Future<void> _created(int id, int attempt) async {
    final channel = MethodChannel('buildify.ai/voice-call/$id');
    if (!mounted || _ended || attempt != _attempt) {
      unawaited(channel.invokeMethod<void>('end').catchError((_) {}));
      return;
    }
    _call?.setMethodCallHandler(null);
    _call = channel;
    Future<void> receive(MethodCall call) async {
      if (!mounted || _ended || _call != channel) return;
      if (call.method == 'ready') {
        _timeout?.cancel();
        setState(() {
          _loading = false;
          _message = null;
        });
      } else if (call.method == 'error') {
        _finish(switch (call.arguments) {
          'microphone_unavailable' =>
            'Microphone access is unavailable. Check Android app permissions and retry.',
          'audio_interrupted' =>
            'Another app interrupted the audio. The call ended.',
          'navigation_blocked' =>
            'The call tried to leave its verified page. Run voice setup again.',
          'webview_unavailable' =>
            'The Android call screen is unavailable. Update Android System WebView and retry.',
          _ =>
            'The voice connection was interrupted. Check your network and retry.',
        });
      } else if (call.method == 'ended') {
        _finish('Call ended. You can start a new call.');
      }
    }

    channel.setMethodCallHandler(receive);
    // Recover events emitted before Flutter attached its channel listener.
    try {
      final state = await channel.invokeMapMethod<String, dynamic>('getState');
      if (!mounted || _ended || _call != channel) return;
      if (state?['error'] != null) {
        await receive(MethodCall('error', state!['error']));
      } else if (state?['ended'] == true) {
        await receive(const MethodCall('ended'));
      } else if (state?['ready'] == true) {
        await receive(const MethodCall('ready'));
      }
    } catch (_) {
      if (mounted && !_ended && _call == channel) {
        _finish(
          'Could not initialize the Android call screen. Update Android System WebView and retry.',
        );
      }
    }
  }

  Future<void> _endNative() async {
    try {
      await _call?.invokeMethod<void>('end');
    } catch (_) {
      // Disposal also closes the native WebView and its media capture.
    }
  }

  void _finish(String message) {
    _timeout?.cancel();
    ++_attempt; // Ignore a permission/verification result from a cancelled attempt.
    unawaited(_endNative());
    if (!mounted) return;
    setState(() {
      _ended = true;
      _ready = false;
      _loading = false;
      _message = message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _finish(
        'Call ended because Buildify left the foreground. Tap Retry when ready.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    ++_attempt;
    unawaited(_endNative());
    _call?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Talk to Buildify')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.target == VoiceRunTarget.phone
                ? 'Runs on this Android phone'
                : 'Runs on your paired laptop',
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message!, semanticsLabel: _message),
          ),
        if (_ready && !_ended)
          Expanded(
            child: AndroidView(
              key: ValueKey(_attempt),
              viewType: 'buildify.ai/voice-call',
              creationParams: {'url': widget.invitation.toString()},
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _createdForAttempt(),
            ),
          )
        else
          const Spacer(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            children: [
              if (_ended)
                FilledButton(onPressed: _prepare, child: const Text('Retry')),
              if (!_ended)
                FilledButton(
                  onPressed:
                      () => _finish('Call ended. You can start a new call.'),
                  child: const Text('End call'),
                ),
              if (widget.target == VoiceRunTarget.phone)
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
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Keep Buildify in the foreground during calls. Bolna processes your voice online.',
          ),
        ),
      ],
    ),
  );

  PlatformViewCreatedCallback _createdForAttempt() {
    final attempt = _attempt;
    return (id) => unawaited(_created(id, attempt));
  }
}
