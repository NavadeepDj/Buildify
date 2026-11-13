import 'host_inspection_service.dart';

enum InspectionToolError { unknownTool, invalidArguments }

class InspectionToolResult {
  const InspectionToolResult.success(this.data) : error = null;
  const InspectionToolResult.failure(this.error) : data = null;

  final Map<String, Object?>? data;
  final InspectionToolError? error;

  Map<String, Object?> toJson() => {
    'ok': error == null,
    if (error != null) 'error': error!.name,
    if (data != null) 'data': data,
  };
}

/// Deliberately read-only. A future planner cannot submit a target device,
/// command, URL or credential through these zero-argument operations.
class AssistantInspectionTools {
  const AssistantInspectionTools(this._inspection);

  final HostInspectionService _inspection;

  static const names = {'get_device_capabilities', 'get_runtime_state'};

  Future<InspectionToolResult> invoke(
    String name, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (!names.contains(name)) {
      return const InspectionToolResult.failure(
        InspectionToolError.unknownTool,
      );
    }
    if (arguments.isNotEmpty) {
      return const InspectionToolResult.failure(
        InspectionToolError.invalidArguments,
      );
    }
    if (name == 'get_device_capabilities') {
      final reading = await _inspection.readDeviceCapabilities();
      return InspectionToolResult.success(
        reading.toJson((value) => value.toJson()),
      );
    }
    return InspectionToolResult.success(
      (await _inspection.readRuntimeState()).toJson(),
    );
  }
}
