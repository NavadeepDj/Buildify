import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'native_server_bridge.dart';
import 'server_bridge_factory.dart';

/// Only the connector token belongs on the device hosting the project.
/// DNS/account API credentials remain on the setup-script host.
class ProjectGateway {
  ProjectGateway({
    ServerBridge? bridge,
    Future<String?> Function()? buildTokenLoader,
  }) : _bridge = bridge ?? createServerBridge(),
       _buildTokenLoader = buildTokenLoader ?? _androidBuildToken;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'buildiify_gateway_connector_token';
  final ServerBridge _bridge;
  final Future<String?> Function() _buildTokenLoader;
  static Future<String?> _androidBuildToken() async {
    if (!Platform.isAndroid) return null;
    try {
      return await const MethodChannel(
        'buildify.ai/server',
      ).invokeMethod<String>('getGatewayConnectorToken');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void>? _starting;
  Future<String?> _token() async {
    final token = Platform.environment['CF_TUNNEL_TOKEN']?.trim();
    if (token != null && token.isNotEmpty) return token;
    // Private Android builds load the local .env with --dart-define-from-file.
    // Android does not inherit the build machine's process environment.
    const bundled = String.fromEnvironment('CF_TUNNEL_TOKEN');
    final buildToken =
        bundled.trim().isNotEmpty
            ? bundled.trim()
            : (await _buildTokenLoader())?.trim();
    if (buildToken != null && buildToken.isNotEmpty) {
      // Build configuration is usable even if device secure storage is unavailable.
      try {
        await saveToken(buildToken);
      } on PlatformException {
        // The configured build token can still start the connector.
      }
      return buildToken;
    }
    return await _storage.read(key: _tokenKey);
  }

  Future<bool> get configured async => (await _token())?.isNotEmpty ?? false;
  Future<void> saveToken(String value) async {
    final token = value.trim();
    if (token.length < 40 || !RegExp(r'^[A-Za-z0-9_+/=\-]+$').hasMatch(token)) {
      throw const FormatException(
        'Paste only the gateway connector token, not the install command.',
      );
    }
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> start(int routerPort) =>
      _starting ??= _start(routerPort).whenComplete(() => _starting = null);
  Future<void> _start(int routerPort) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const HttpException(
        'Configure the buildiify-gateway connector token to start the project tunnel.',
      );
    }
    final status = await _bridge.getTunnelStatus();
    if (status?.status == 'running' || status?.status == 'starting') {
      if (status!.isGateway && status.status == 'running') return;
      if (status.isGateway) {
        await _waitUntilConnected();
        return;
      }
      throw const HttpException(
        'Stop the existing model tunnel before starting the project gateway.',
      );
    }
    final result = await _bridge.startTunnel(
      port: routerPort,
      tunnelToken: token,
    );
    if (!result.ok) {
      throw HttpException(
        result.message ?? 'Could not start the project gateway',
      );
    }
    await _waitUntilConnected();
  }

  Future<void> _waitUntilConnected() async {
    for (var attempt = 0; attempt < 45; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final status = await _bridge.getTunnelStatus();
      if (status?.status == 'running' && status!.isGateway) return;
      if (status?.status == 'failed' || status?.lastError != null) {
        throw const HttpException(
          'Gateway connection failed. Check the connector token and network connection.',
        );
      }
    }
    throw const HttpException(
      'Gateway connection timed out. Check the connector token and outbound network access.',
    );
  }
}
