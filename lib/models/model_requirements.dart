/// Auditable catalog requirements, separate from display labels and benchmarks.
class ModelRequirements {
  const ModelRequirements({
    required this.bytes,
    required this.sha256,
    required this.sourceRevision,
    required this.license,
    required this.contextTokens,
    required this.runtimeOverheadBytes,
    required this.contextMemoryBytes,
    required this.format,
    required this.runtime,
    this.qualityRank = 0,
    this.tasks = const [],
    this.testedConfigurations = const [],
  });

  final int bytes;
  final String sha256;
  final String sourceRevision;
  final String license;
  final int contextTokens;
  final int runtimeOverheadBytes;
  final int contextMemoryBytes;
  final String format;
  final String runtime;
  final int qualityRank;
  final List<String> tasks;
  final List<String> testedConfigurations;

  int get estimatedMemoryBytes =>
      bytes + runtimeOverheadBytes + contextMemoryBytes;

  static ModelRequirements? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? positive(String key) {
      final v = raw[key];
      return v is int && v > 0 ? v : null;
    }

    final bytes = positive('bytes');
    final context = positive('contextTokens');
    final overhead = positive('runtimeOverheadBytes');
    final cache = positive('contextMemoryBytes');
    final hash = raw['sha256'];
    final revision = raw['sourceRevision'];
    final license = raw['license'];
    final format = raw['format'];
    final runtime = raw['runtime'];
    final rank = raw['qualityRank'];
    if (bytes == null ||
        context == null ||
        overhead == null ||
        cache == null ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        revision is! String ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(revision) ||
        license is! String ||
        license.isEmpty ||
        format is! String ||
        runtime is! String ||
        rank is! int ||
        rank < 0) {
      return null;
    }
    List<String> strings(String key) => List.unmodifiable(
      (raw[key] is List ? raw[key] as List : const []).whereType<String>(),
    );
    return ModelRequirements(
      bytes: bytes,
      sha256: hash,
      sourceRevision: revision,
      license: license,
      contextTokens: context,
      runtimeOverheadBytes: overhead,
      contextMemoryBytes: cache,
      format: format,
      runtime: runtime,
      qualityRank: rank,
      tasks: strings('tasks'),
      testedConfigurations: strings('testedConfigurations'),
    );
  }
}
