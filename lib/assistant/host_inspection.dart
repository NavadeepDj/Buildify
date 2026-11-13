/// Sanitized, local-only observations for assistant planning.
///
/// A bridge read is not an inference/health test or proof that a runtime binary
/// is installed. Missing values must never be replaced with UI defaults.
enum InspectionStatus {
  observed,
  partial,
  unavailable,
  unsupported,
  timedOut,
  failed,
  invalid,
}

enum AssistantHostPlatform { android, windows, macos, linux, ios, unknown }

enum ObservedRuntimeState {
  stopped,
  starting,
  running,
  stopping,
  failed,
  unknown,
}

class InspectionReading<T> {
  InspectionReading({
    required this.status,
    required DateTime readAt,
    this.value,
  }) : readAt = readAt.toUtc();

  final InspectionStatus status;
  final DateTime readAt;
  final T? value;

  Map<String, Object?> toJson(Map<String, Object?> Function(T) encode) => {
    'status': status.name,
    'readAt': readAt.toIso8601String(),
    'source': 'local_runtime_bridge',
    'value': value == null ? null : encode(value as T),
  };
}

class AssistantDeviceCapabilities {
  AssistantDeviceCapabilities({
    required this.platform,
    this.totalMemoryGiB,
    this.availableMemoryGiB,
    this.freeStorageGiB,
    this.batteryPercent,
    this.batteryCharging,
    Iterable<String> invalidFields = const [],
  }) : invalidFields = List.unmodifiable(invalidFields);

  final AssistantHostPlatform platform;
  final double? totalMemoryGiB;
  final double? availableMemoryGiB;
  final double? freeStorageGiB;
  final int? batteryPercent;
  final bool? batteryCharging;
  final List<String> invalidFields;

  /// These are deliberately not inferred from the host OS or process state.
  /// Probing ABI/binary/version compatibility is a later capability extension.
  Map<String, Object?> toJson() => {
    'platform': platform.name,
    'totalMemoryGiB': totalMemoryGiB,
    'availableMemoryGiB': availableMemoryGiB,
    'freeStorageGiB': freeStorageGiB,
    'batteryPercent': batteryPercent,
    'batteryCharging': batteryCharging,
    'architecture': null,
    'inferenceRuntimeAvailable': null,
    'invalidFields': invalidFields,
  };

  bool get isComplete =>
      totalMemoryGiB != null &&
      availableMemoryGiB != null &&
      freeStorageGiB != null &&
      batteryPercent != null &&
      batteryCharging != null &&
      invalidFields.isEmpty;

  factory AssistantDeviceCapabilities.fromMetrics(
    AssistantHostPlatform platform,
    Map<String, dynamic> metrics,
  ) {
    final invalid = <String>[];
    double? number(String key, {bool positive = false}) {
      final raw = metrics[key];
      if (raw == null) return null;
      if (raw is num && raw.isFinite && (positive ? raw > 0 : raw >= 0)) {
        return raw.toDouble();
      }
      invalid.add(key);
      return null;
    }

    final total = number('ramGb', positive: true);
    var available = number('availRamGb');
    final storage = number('freeStorageGb');
    if (total != null && available != null && available > total) {
      invalid.add('availRamGb');
      available = null;
    }
    final battery = number('batteryPercent');
    int? percent;
    if (battery != null) {
      if (battery <= 100 && battery == battery.roundToDouble()) {
        percent = battery.toInt();
      } else {
        invalid.add('batteryPercent');
      }
    }
    final charging = metrics['batteryCharging'];
    if (charging != null && charging is! bool) invalid.add('batteryCharging');

    return AssistantDeviceCapabilities(
      platform: platform,
      totalMemoryGiB: total,
      availableMemoryGiB: available,
      freeStorageGiB: storage,
      batteryPercent: percent,
      batteryCharging: charging is bool ? charging : null,
      invalidFields: invalid,
    );
  }
}

class AssistantProcessObservation {
  const AssistantProcessObservation({required this.state, this.port});

  final ObservedRuntimeState state;
  final int? port;

  Map<String, Object?> toJson() => {'state': state.name, 'port': port};
}

class AssistantTunnelObservation {
  const AssistantTunnelObservation({
    required this.state,
    required this.isGateway,
  });

  final ObservedRuntimeState state;
  final bool isGateway;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'isGateway': isGateway,
  };
}

class AssistantRuntimeSnapshot {
  const AssistantRuntimeSnapshot({required this.server, required this.tunnel});

  final InspectionReading<AssistantProcessObservation> server;
  final InspectionReading<AssistantTunnelObservation> tunnel;

  Map<String, Object?> toJson() => {
    'server': server.toJson((value) => value.toJson()),
    'tunnel': tunnel.toJson((value) => value.toJson()),
    'healthVerified': false,
  };
}
