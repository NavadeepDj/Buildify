import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Buildify Discovery Beacon Service
/// Listens on UDP broadcast port 8257 for discovery requests from Buildify SDKs
/// and responds with the device's server details and status.
class BuildifyDiscoveryBeacon {
  static const int beaconPort = 8257;
  RawDatagramSocket? _socket;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Starts listening for discovery broadcasts from Buildify SDK clients.
  Future<void> start({
    required int serverPort,
    String? modelName,
    String? tunnelUrl,
    InternetAddress? bindAddress,
  }) async {
    if (_isRunning) return;

    try {
      _socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
      );
      _socket?.broadcastEnabled = true;
      _isRunning = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram == null) return;

          try {
            final message = utf8.decode(datagram.data).trim();
            if (message.startsWith('BUILDIFY_DISCOVER')) {
              final payload = jsonEncode({
                'service': 'buildify-ai',
                'version': '1.0.0',
                'port': serverPort,
                'model': modelName ?? 'default',
                'tunnel_url': tunnelUrl,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });

              final replyBytes = utf8.encode(payload);
              _socket?.send(replyBytes, datagram.address, datagram.port);
            }
          } catch (_) {}
        }
      });
    } catch (_) {
      // Ignored if port is occupied or socket fails
      _isRunning = false;
    }
  }

  /// Stops the beacon service.
  void stop() {
    _isRunning = false;
    _socket?.close();
    _socket = null;
  }
}
