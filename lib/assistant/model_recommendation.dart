import '../models/ai_server_models.dart';
import 'host_inspection.dart';

enum ModelPreference { speed, balanced, quality }

/// A bounded, host-local runtime observation. Unknown support stays unknown.
class RuntimeCompatibility {
  const RuntimeCompatibility({
    required this.readAt,
    required this.platform,
    this.available,
    this.runtime,
    this.supportedModelIds = const {},
  });
  final DateTime readAt;
  final AssistantHostPlatform platform;
  final bool? available;
  final String? runtime;
  final Set<String> supportedModelIds;
}

class VerifiedInstalledModel {
  const VerifiedInstalledModel({
    required this.id,
    required this.sha256,
    required this.bytes,
  });
  final String id;
  final String sha256;
  final int bytes;
}

class ModelCandidate {
  ModelCandidate({
    required this.model,
    required this.reuseInstalled,
    required Iterable<String> blockers,
  }) : blockers = List.unmodifiable(blockers);
  final ModelProfile model;
  final bool reuseInstalled;
  final List<String> blockers;
  bool get eligible => blockers.isEmpty;
  Map<String, Object?> toJson() => {
    'modelId': model.id,
    'eligible': eligible,
    'blockers': blockers,
    'reuseInstalled': reuseInstalled,
    'downloadBytes': reuseInstalled ? 0 : model.requirements?.bytes,
    'estimatedMemoryBytes': model.requirements?.estimatedMemoryBytes,
    'contextTokens': model.requirements?.contextTokens,
    'estimateKind': 'conservative_budget_not_benchmark',
    'performanceVerified': false,
  };
}

class ModelRecommendation {
  ModelRecommendation(Iterable<ModelCandidate> candidates)
    : candidates = List.unmodifiable(candidates);
  final List<ModelCandidate> candidates;
  ModelCandidate? get recommended =>
      candidates.where((c) => c.eligible).firstOrNull;
  ModelCandidate? get smallerFallback {
    final primary = recommended;
    if (primary == null) return null;
    final smaller =
        candidates
            .where(
              (c) =>
                  c.eligible &&
                  c.model.requirements!.bytes <
                      primary.model.requirements!.bytes,
            )
            .toList()
          ..sort(
            (a, b) => b.model.requirements!.bytes.compareTo(
              a.model.requirements!.bytes,
            ),
          );
    return smaller.firstOrNull;
  }
}

class ModelRecommendationService {
  const ModelRecommendationService({
    this.maxAge = const Duration(seconds: 30),
    this.memoryReserveBytes = 512 * 1024 * 1024,
    this.storageReserveBytes = 256 * 1024 * 1024,
  });
  final Duration maxAge;
  final int memoryReserveBytes;
  final int storageReserveBytes;

  ModelRecommendation recommend({
    required List<ModelProfile> models,
    required InspectionReading<AssistantDeviceCapabilities> device,
    required RuntimeCompatibility runtime,
    required DateTime now,
    ModelPreference preference = ModelPreference.balanced,
    String task = 'short_answers',
    List<VerifiedInstalledModel> installed = const [],
  }) {
    bool fresh(DateTime read) =>
        !read.isAfter(now) && now.difference(read) <= maxAge;
    final metrics = device.value;
    final trustedMetrics =
        device.status == InspectionStatus.observed ||
        device.status == InspectionStatus.partial;
    final candidates =
        models.map((model) {
          final requirements = model.requirements;
          final blockers = <String>[];
          final reuse =
              requirements != null &&
              installed.any(
                (i) =>
                    i.id == model.id &&
                    i.sha256 == requirements.sha256 &&
                    i.bytes == requirements.bytes,
              );
          if (requirements == null) blockers.add('catalog_metadata_unverified');
          if (!trustedMetrics || metrics == null || !fresh(device.readAt)) {
            blockers.add('fresh_device_metrics_required');
          }
          if (!fresh(runtime.readAt) ||
              metrics == null ||
              runtime.platform != metrics.platform ||
              runtime.available == null ||
              runtime.runtime == null) {
            blockers.add('runtime_verification_required');
          } else if (!runtime.available!) {
            blockers.add('runtime_unavailable');
          } else if (requirements != null &&
              (runtime.runtime != requirements.runtime ||
                  !runtime.supportedModelIds.contains(model.id))) {
            blockers.add('runtime_model_unsupported');
          }
          if (requirements != null) {
            if (requirements.format != 'gguf') {
              blockers.add('format_unsupported');
            }
            final available = metrics?.availableMemoryGiB;
            if (available == null || !available.isFinite || available < 0) {
              blockers.add('available_memory_unknown');
            } else if (available * 1073741824 <
                requirements.estimatedMemoryBytes + memoryReserveBytes) {
              blockers.add('insufficient_memory');
            }
            if (!reuse) {
              final disk = metrics?.freeStorageGiB;
              if (disk == null || !disk.isFinite || disk < 0) {
                blockers.add('free_storage_unknown');
              } else if (disk * 1073741824 <
                  requirements.bytes + storageReserveBytes) {
                blockers.add('insufficient_storage');
              }
            }
          }
          return ModelCandidate(
            model: model,
            reuseInstalled: reuse,
            blockers: blockers,
          );
        }).toList();
    candidates.sort((a, b) {
      if (a.eligible != b.eligible) return a.eligible ? -1 : 1;
      final ar = a.model.requirements;
      final br = b.model.requirements;
      if (ar == null || br == null) return a.model.id.compareTo(b.model.id);
      final at = ar.tasks.contains(task);
      final bt = br.tasks.contains(task);
      if (at != bt) return at ? -1 : 1;
      if (a.reuseInstalled != b.reuseInstalled) {
        return a.reuseInstalled ? -1 : 1;
      }
      final rank = switch (preference) {
        ModelPreference.speed => ar.bytes.compareTo(br.bytes),
        ModelPreference.quality => br.qualityRank.compareTo(ar.qualityRank),
        ModelPreference.balanced => (ar.qualityRank - 2).abs().compareTo(
          (br.qualityRank - 2).abs(),
        ),
      };
      if (rank != 0) return rank;
      return a.model.id.compareTo(b.model.id);
    });
    return ModelRecommendation(candidates);
  }
}
