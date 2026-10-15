import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:buildify_flutter/services/project_gateway.dart';
import 'package:buildify_flutter/services/subdomain.dart';

class FakeTunnelBridge implements ServerBridge {
  FakeTunnelBridge({this.quickTunnel = false});
  final bool quickTunnel;
  int starts = 0;
  int? port;
  String? token;
  @override
  Future<NativeTunnelStatus?> getTunnelStatus() async => NativeTunnelStatus(
    status: quickTunnel || starts > 0 ? 'running' : 'stopped',
    isGateway: !quickTunnel && starts > 0,
    publicUrl: quickTunnel ? 'https://example.trycloudflare.com' : null,
  );
  @override
  Future<NativeTunnelResponse> startTunnel({
    required int port,
    String? tunnelUrl,
    String? tunnelToken,
  }) async {
    starts++;
    this.port = port;
    token = tunnelToken;
    return const NativeTunnelResponse(ok: true, status: 'starting');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Android build configuration supplies token without Dart defines',
    () async {
      final bridge = FakeTunnelBridge();
      final gateway = ProjectGateway(
        bridge: bridge,
        buildTokenLoader: () async => 'b' * 60,
      );
      expect(await gateway.configured, true);
      await gateway.start(8787);
      expect(bridge.starts, 1);
      expect(bridge.token?.length, 60);
      expect(
        await const FlutterSecureStorage().read(
          key: 'buildiify_gateway_connector_token',
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'configured private build replaces stale saved connector token',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'buildiify_gateway_connector_token': 'old',
      });
      final bridge = FakeTunnelBridge();
      final gateway = ProjectGateway(
        bridge: bridge,
        buildTokenLoader: () async => 'b' * 60,
      );
      await gateway.start(8787);
      expect(bridge.token?.length, 60);
    },
  );
  test(
    'private build imports connector token without prompting',
    () async {
      final gateway = ProjectGateway(bridge: FakeTunnelBridge());
      expect(await gateway.configured, true);
      final stored = await const FlutterSecureStorage().read(
        key: 'buildiify_gateway_connector_token',
      );
      expect(stored?.isNotEmpty, true);
    },
    skip: const String.fromEnvironment('CF_TUNNEL_TOKEN').isEmpty,
  );
  test('project name label is normalized and fits one DNS level', () {
    expect(projectNameSubdomain('My Project!'), 'my-project');
    expect(validateSubdomain(projectNameSubdomain('A' * 100)), isNull);
    expect(projectNameSubdomain('...'), 'project');
  });
  test(
    'gateway saves connector token securely and deduplicates starts',
    () async {
      final bridge = FakeTunnelBridge();
      final gateway = ProjectGateway(bridge: bridge);
      final token = 'a' * 60;
      await gateway.saveToken(token);
      expect(await gateway.configured, true);
      await Future.wait([gateway.start(8787), gateway.start(8787)]);
      expect(bridge.starts, 1);
      expect(bridge.port, 8787);
      expect(bridge.token, token);
      await gateway.start(8787);
      expect(bridge.starts, 1);
    },
  );
  test('a model quick tunnel is never replaced by the gateway', () async {
    final bridge = FakeTunnelBridge(quickTunnel: true);
    final gateway = ProjectGateway(bridge: bridge);
    await gateway.saveToken('a' * 60);
    await expectLater(gateway.start(8787), throwsA(isA<HttpException>()));
    expect(bridge.starts, 0);
  });
  test('install command is rejected rather than stored as a token', () async {
    final gateway = ProjectGateway(bridge: FakeTunnelBridge());
    await expectLater(
      gateway.saveToken('cloudflared tunnel run --token ${'a' * 60}'),
      throwsFormatException,
    );
    expect(await gateway.configured, false);
  });
}
