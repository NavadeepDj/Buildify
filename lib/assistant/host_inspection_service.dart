import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../services/native_server_bridge.dart';
import 'host_inspection.dart';

/// Reads the caller's existing bridge without starting another runtime owner.
/// Only allowlisted, typed observations cross the assistant boundary.
class HostInspectionService {
  HostInspectionService({
    required ServerBridge bridge,
    AssistantHostPlatform? platform,
    DateTime Function()? clock,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _bridge = bridge,
       platform = platform ?? _currentPlatform(),
       _clock = clock ?? DateTime.now {
    if (probeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        probeTimeout,
        'probeTimeout',
        'Must be positive',
      );
    }
  }

  final ServerBridge _bridge;
  final DateTime Function() _clock;
  final AssistantHostPlatform platform;
  final Duration probeTimeout;

  static AssistantHostPlatform _currentPlatform() {
    if (Platform.isAndroid) return AssistantHostPlatform.android;
    if (Platform.isWindows) return AssistantHostPlatform.windows;
    if (Platform.isMacOS) return AssistantHostPlatform.macos;
    if (Platform.isLinux) return AssistantHostPlatform.linux;
    if (Platform.isIOS) return AssistantHostPlatform.ios;
    return AssistantHostPlatform.unknown;
  }

  Future<InspectionReading<R>> _probe<T, R>(
    Future<T?> Function() read,
    R Function(T) sanitize,
    InspectionStatus Function(R) classify,
  ) async {
    try {
      final raw = await Future<T?>.sync(read).timeout(probeTimeout);
      if (raw == null) {
        return InspectionReading(
          status: InspectionStatus.unavailable,
          readAt: _clock(),
        );
      }
      final value = sanitize(raw);
      return InspectionReading(
        status: classify(value),
        readAt: _clock(),
        value: value,
      );
    } on TimeoutException {
      return InspectionReading(
        status: InspectionStatus.timedOut,
        readAt: _clock(),
      );
    } on MissingPluginException {
      return InspectionReading(
        status: InspectionStatus.unsupported,
        readAt: _clock(),
      );
    } on UnsupportedError {
      return InspectionReading(
        status: InspectionStatus.unsupported,
        readAt: _clock(),
      );
    } catch (_) {
      // Never serialize exception strings: native failures may contain paths,
      // connector credentials, URLs or unrelated host configuration.
      return InspectionReading(
        status: InspectionStatus.failed,
        readAt: _clock(),
      );
    }
  }

  Future<InspectionReading<AssistantDeviceCapabilities>>
  readDeviceCapabilities() =>
      _probe<Map<String, dynamic>, AssistantDeviceCapabilities>(
        _bridge.getDeviceMetrics,
        (metrics) => AssistantDeviceCapabilities.fromMetrics(platform, metrics),
        (value) =>
            value.isComplete
                ? InspectionStatus.observed
                : InspectionStatus.partial,
      );

  Future<AssistantRuntimeSnapshot> readRuntimeState() async {
    // Start independent reads together; one unavailable probe does not discard
    // the other observation or double the timeout budget.
    final server = _probe<NativeServerStatus, AssistantProcessObservation>(
      _bridge.getServerStatus,
      (status) => AssistantProcessObservation(
        state: _state(status.status),
        port: status.port >= 1 && status.port <= 65535 ? status.port : null,
      ),
      (value) =>
          value.state == ObservedRuntimeState.unknown || value.port == null
              ? InspectionStatus.invalid
              : InspectionStatus.observed,
    );
    final tunnel = _probe<NativeTunnelStatus, AssistantTunnelObservation>(
      _bridge.getTunnelStatus,
      (status) => AssistantTunnelObservation(
        state: _state(status.status),
        isGateway: status.isGateway,
      ),
      (value) =>
          value.state == ObservedRuntimeState.unknown
              ? InspectionStatus.invalid
              : InspectionStatus.observed,
    );
    return AssistantRuntimeSnapshot(server: await server, tunnel: await tunnel);
  }

  static ObservedRuntimeState _state(String raw) => switch (raw) {
    'stopped' => ObservedRuntimeState.stopped,
    'starting' => ObservedRuntimeState.starting,
    'running' => ObservedRuntimeState.running,
    'stopping' => ObservedRuntimeState.stopping,
    'failed' => ObservedRuntimeState.failed,
    _ => ObservedRuntimeState.unknown,
  };
}
