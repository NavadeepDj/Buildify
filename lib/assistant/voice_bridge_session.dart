import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'status_probe_provider.dart';

/// An explicitly enabled, memory-only owner pairing for this app session.
/// Never compile a Bolna API key or a shared bridge token into an APK.
class VoiceBridgeSession {
  const VoiceBridgeSession({required this.token, this.port = 18791});

  factory VoiceBridgeSession.create() {
    final random = Random.secure();
    return VoiceBridgeSession(
      token: base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', ''),
    );
  }

  final String token;
  final int port;
}

final voiceBridgeSessionProvider =
    StateNotifierProvider<VoiceBridgeSessionController, VoiceBridgeSession?>(
      (ref) => VoiceBridgeSessionController(ref),
    );

class VoiceBridgeSessionController extends StateNotifier<VoiceBridgeSession?> {
  VoiceBridgeSessionController(this._ref) : super(null);

  final Ref _ref;
  Future<void>? _stopping;

  VoiceBridgeSession enable() {
    if (_stopping != null) {
      throw StateError('Wait for the previous voice session to disconnect.');
    }
    return state ??= VoiceBridgeSession.create();
  }

  Future<void> disable() =>
      _stopping ??= _disable().whenComplete(() {
        _stopping = null;
      });

  Future<void> _disable() async {
    if (state == null) return;
    try {
      final server = await _ref.read(statusProbeProvider.future);
      await server?.close();
    } catch (_) {
      // A failed startup has no usable bridge. Clearing the pairing allows retry.
    } finally {
      if (mounted) state = null;
    }
  }
}
