import 'dart:async';
import 'dart:convert';

import 'package:buildify_flutter/assistant/host_inspection.dart';
import 'package:buildify_flutter/assistant/host_inspection_service.dart';
import 'package:buildify_flutter/assistant/inspection_tools.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/services/native_server_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReadOnlyBridge implements ServerBridge {
  Map<String, dynamic>? metrics = {
    'ramGb': 8,
    'availRamGb': 3.5,
    'freeStorageGb': 12.0,
    'batteryPercent': 80,
    'batteryCharging': false,
  };
  Future<Map<String, dynamic>?> Function()? metricsRead;
  Future<NativeServerStatus?> Function()? serverRead;
  Future<NativeTunnelStatus?> Function()? tunnelRead;
  int metricsCalls = 0;
  int serverCalls = 0;
  int tunnelCalls = 0;
  final unexpectedCalls = <Symbol>[];

  @override
  Future<Map<String, dynamic>?> getDeviceMetrics() async {
    metricsCalls++;
    return metricsRead == null ? metrics : await metricsRead!();
  }

  @override
  Future<NativeServerStatus?> getServerStatus() async {
    serverCalls++;
    return serverRead == null
        ? const NativeServerStatus(status: 'running', port: 8080)
        : await serverRead!();
  }

  @override
  Future<NativeTunnelStatus?> getTunnelStatus() async {
    tunnelCalls++;
    return tunnelRead == null
        ? const NativeTunnelStatus(status: 'stopped')
        : await tunnelRead!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName);
    throw StateError('Unexpected runtime operation');
  }
}

void main() {
  late _ReadOnlyBridge bridge;
  late DateTime now;
  late HostInspectionService service;
  setUp(() {
    bridge = _ReadOnlyBridge();
    now = DateTime.parse('2026-11-13T10:00:00+05:30');
    service = HostInspectionService(
      bridge: bridge,
      platform: AssistantHostPlatform.android,
      clock: () => now,
    );
  });

  test(
    'reads fresh measurements each call without claiming binary support',
    () async {
      final first = await service.readDeviceCapabilities();
      expect(first.status, InspectionStatus.observed);
      expect(first.value!.availableMemoryGiB, 3.5);
      expect(first.readAt.toIso8601String(), '2026-11-13T04:30:00.000Z');
      bridge.metrics!['availRamGb'] = 1.25;
      now = now.add(const Duration(seconds: 4));
      final second = await service.readDeviceCapabilities();
      expect(second.value!.availableMemoryGiB, 1.25);
      expect(second.readAt.isAfter(first.readAt), isTrue);
      expect(bridge.metricsCalls, 2);
      final data = second.value!.toJson();
      expect(data['architecture'], isNull);
      expect(data['inferenceRuntimeAvailable'], isNull);
      expect(bridge.unexpectedCalls, isEmpty);
    },
  );

  test('partial and absent metrics never borrow UI defaults', () async {
    bridge.metrics = {'batteryPercent': 0, 'batteryCharging': false};
    final partial = await service.readDeviceCapabilities();
    expect(partial.status, InspectionStatus.partial);
    expect(partial.value!.batteryPercent, 0);
    expect(partial.value!.batteryCharging, isFalse);
    expect(partial.value!.availableMemoryGiB, isNull);
    expect(partial.value!.totalMemoryGiB, isNull);
    expect(partial.value!.freeStorageGiB, isNull);
    bridge.metrics = null;
    final absent = await service.readDeviceCapabilities();
    expect(absent.status, InspectionStatus.unavailable);
    expect(absent.value, isNull);
  });

  test('rejects invalid/nonfinite metrics and inconsistent memory', () async {
    bridge.metrics = {
      'ramGb': 4,
      'availRamGb': 5,
      'freeStorageGb': double.infinity,
      'batteryPercent': 101,
      'batteryCharging': 'yes',
    };
    final reading = await service.readDeviceCapabilities();
    expect(reading.status, InspectionStatus.partial);
    expect(reading.value!.totalMemoryGiB, 4);
    expect(reading.value!.availableMemoryGiB, isNull);
    expect(reading.value!.freeStorageGiB, isNull);
    expect(reading.value!.batteryPercent, isNull);
    expect(reading.value!.batteryCharging, isNull);
    expect(
      reading.value!.invalidFields,
      unorderedEquals([
        'availRamGb',
        'freeStorageGb',
        'batteryPercent',
        'batteryCharging',
      ]),
    );
    expect(
      () => jsonEncode(reading.toJson((v) => v.toJson())),
      returnsNormally,
    );
  });

  test(
    'does not coerce strings, NaN, negative, zero total or fractional battery',
    () async {
      for (final metrics in <Map<String, dynamic>>[
        {
          'ramGb': 0,
          'availRamGb': -1,
          'freeStorageGb': double.nan,
          'batteryPercent': 10.5,
        },
        {
          'ramGb': '8',
          'availRamGb': '4',
          'freeStorageGb': '12',
          'batteryPercent': -1,
        },
      ]) {
        bridge.metrics = metrics;
        final value = (await service.readDeviceCapabilities()).value!;
        expect(value.totalMemoryGiB, isNull);
        expect(value.availableMemoryGiB, isNull);
        expect(value.freeStorageGiB, isNull);
        expect(value.batteryPercent, isNull);
      }
      bridge.metrics = {'availRamGb': 0, 'freeStorageGb': 0};
      final zero = (await service.readDeviceCapabilities()).value!;
      expect(zero.availableMemoryGiB, 0);
      expect(zero.freeStorageGiB, 0);
    },
  );

  test(
    'unimplemented bridges and failed probes have stable safe statuses',
    () async {
      bridge.metricsRead = () => throw MissingPluginException('secret-path');
      expect(
        (await service.readDeviceCapabilities()).status,
        InspectionStatus.unsupported,
      );
      bridge.metricsRead = () => throw UnsupportedError('secret-token');
      expect(
        (await service.readDeviceCapabilities()).status,
        InspectionStatus.unsupported,
      );
      bridge.metricsRead =
          () => throw StateError('secret-token /private/model.gguf');
      final failed = await service.readDeviceCapabilities();
      expect(failed.status, InspectionStatus.failed);
      expect(failed.value, isNull);
      expect(
        jsonEncode(failed.toJson((v) => v.toJson())),
        isNot(contains('secret')),
      );
    },
  );

  test('bounds hung probes and ignores late results', () async {
    final pending = Completer<Map<String, dynamic>?>();
    bridge.metricsRead = () => pending.future;
    final bounded = HostInspectionService(
      bridge: bridge,
      probeTimeout: const Duration(milliseconds: 10),
    );
    final reading = await bounded.readDeviceCapabilities();
    expect(reading.status, InspectionStatus.timedOut);
    pending.complete(bridge.metrics);
    await Future<void>.delayed(Duration.zero);
    expect(reading.value, isNull);
  });

  test('runtime probes are independent and do not claim health', () async {
    bridge.serverRead = () async => throw StateError('secret native failure');
    final snapshot = await service.readRuntimeState();
    expect(snapshot.server.status, InspectionStatus.failed);
    expect(snapshot.tunnel.status, InspectionStatus.observed);
    expect(snapshot.tunnel.value!.state, ObservedRuntimeState.stopped);
    expect(snapshot.toJson()['healthVerified'], isFalse);
    expect(bridge.serverCalls, 1);
    expect(bridge.tunnelCalls, 1);
    expect(bridge.unexpectedCalls, isEmpty);
  });

  test('starts both runtime reads before waiting for completion', () async {
    final server = Completer<NativeServerStatus?>();
    bridge.serverRead = () => server.future;
    bridge.tunnelRead = () async {
      expect(bridge.serverCalls, 1);
      server.complete(const NativeServerStatus(status: 'stopped', port: 8080));
      return const NativeTunnelStatus(status: 'running');
    };
    final result = await service.readRuntimeState();
    expect(result.server.status, InspectionStatus.observed);
    expect(result.tunnel.value!.state, ObservedRuntimeState.running);
  });

  test('unknown raw states and out-of-range ports stay invalid', () async {
    bridge.serverRead =
        () async => const NativeServerStatus(
          status: 'secret-malformed-state',
          port: 70000,
        );
    bridge.tunnelRead =
        () async => const NativeTunnelStatus(status: 'unknown-secret');
    final snapshot = await service.readRuntimeState();
    expect(snapshot.server.status, InspectionStatus.invalid);
    expect(snapshot.server.value!.state, ObservedRuntimeState.unknown);
    expect(snapshot.server.value!.port, isNull);
    expect(snapshot.tunnel.status, InspectionStatus.invalid);
    expect(jsonEncode(snapshot.toJson()), isNot(contains('secret')));
  });

  test(
    'serialization excludes native paths, URLs, errors and extra metrics',
    () async {
      bridge.metrics!['cpuLabel'] = 'private-host-name';
      bridge.metrics!['apiKey'] = 'secret-value';
      bridge.serverRead =
          () async => const NativeServerStatus(
            status: 'running',
            port: 8080,
            modelPath: '/private/model.gguf',
            lastError: 'secret-value',
            stopReason: 'private-stop-message',
          );
      bridge.tunnelRead =
          () async => const NativeTunnelStatus(
            status: 'running',
            isGateway: true,
            publicUrl: 'https://private-host.example/?token=secret-value',
            lastError: 'secret-value',
          );
      final tools = AssistantInspectionTools(service);
      final device = await tools.invoke('get_device_capabilities');
      final runtime = await tools.invoke('get_runtime_state');
      final encoded = jsonEncode([device.toJson(), runtime.toJson()]);
      expect(encoded, isNot(contains('private')));
      expect(encoded, isNot(contains('secret')));
      expect(encoded, isNot(contains('model.gguf')));
      expect(runtime.data!['healthVerified'], isFalse);
      expect(bridge.unexpectedCalls, isEmpty);
    },
  );

  test('rejects unknown tools and arguments before probing', () async {
    final tools = AssistantInspectionTools(service);
    final unknown = await tools.invoke('start_server secret');
    expect(unknown.error, InspectionToolError.unknownTool);
    for (final name in AssistantInspectionTools.names) {
      final invalid = await tools.invoke(
        name,
        arguments: {'deviceId': 'other-owner'},
      );
      expect(invalid.error, InspectionToolError.invalidArguments);
    }
    expect(jsonEncode(unknown.toJson()), isNot(contains('secret')));
    expect(bridge.metricsCalls + bridge.serverCalls + bridge.tunnelCalls, 0);
    expect(bridge.unexpectedCalls, isEmpty);
  });

  test(
    'reading tools does not initialize controller or embedded backend',
    () async {
      final container = ProviderContainer(
        overrides: [
          serverBridgeProvider.overrideWithValue(bridge),
          embeddedBackendProvider.overrideWith(
            (ref) => throw StateError('must not initialize'),
          ),
          aiServerProvider.overrideWith(
            (ref) => throw StateError('must not hydrate runtime'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final tools = container.read(assistantInspectionToolsProvider);
      expect((await tools.invoke('get_runtime_state')).error, isNull);
      expect((await tools.invoke('get_device_capabilities')).error, isNull);
      expect(bridge.metricsCalls, 1);
      expect(bridge.serverCalls, 1);
      expect(bridge.unexpectedCalls, isEmpty);
    },
  );

  test('requires a positive timeout', () {
    expect(
      () => HostInspectionService(bridge: bridge, probeTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
