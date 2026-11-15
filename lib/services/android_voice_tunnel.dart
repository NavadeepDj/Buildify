import 'package:flutter/services.dart';

/// Separate from model/project routing; exposes only the authenticated voice
/// bridge using an ephemeral HTTPS quick tunnel. No account key is required.
class AndroidVoiceTunnel {
  const AndroidVoiceTunnel();

  static const _channel = MethodChannel('buildify.ai/voice');

  Future<Map<String, dynamic>> start({int port = 18791}) =>
      _invoke('startTunnel', {'port': port});

  Future<Map<String, dynamic>> status() => _invoke('getTunnelStatus');

  Future<Map<String, dynamic>> stop() => _invoke('stopTunnel');

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
            method,
            arguments,
          ) ??
          {
            'ok': false,
            'status': 'failed',
            'lastError': 'Voice tunnel unavailable.',
          };
    } on PlatformException {
      return {
        'ok': false,
        'status': 'failed',
        'lastError': 'Voice tunnel unavailable.',
      };
    } on MissingPluginException {
      return {
        'ok': false,
        'status': 'failed',
        'lastError': 'Voice tunnel requires the Android app.',
      };
    }
  }
}
