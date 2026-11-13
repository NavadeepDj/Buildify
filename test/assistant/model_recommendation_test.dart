import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/assistant/host_inspection.dart';
import 'package:buildify_flutter/assistant/model_recommendation.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 13);
  final raw =
      (jsonDecode(File('assets/models/catalog.json').readAsStringSync())
              as Map<String, dynamic>)['models']
          as List;
  final models =
      raw.map((m) => ModelProfile.fromJson(m as Map<String, dynamic>)).toList();
  final ids = models.map((m) => m.id).toSet();
  RuntimeCompatibility runtime({
    bool? available = true,
    DateTime? readAt,
    Set<String>? supported,
    AssistantHostPlatform platform = AssistantHostPlatform.windows,
  }) => RuntimeCompatibility(
    readAt: readAt ?? now,
    platform: platform,
    available: available,
    runtime: 'llama.cpp',
    supportedModelIds: supported ?? ids,
  );
  InspectionReading<AssistantDeviceCapabilities> device({
    double? memory = 8,
    double? disk = 20,
    DateTime? readAt,
    InspectionStatus status = InspectionStatus.observed,
  }) => InspectionReading(
    status: status,
    readAt: readAt ?? now,
    value: AssistantDeviceCapabilities(
      platform: AssistantHostPlatform.windows,
      availableMemoryGiB: memory,
      freeStorageGiB: disk,
    ),
  );
  const service = ModelRecommendationService();
  ModelRecommendation result({
    ModelPreference preference = ModelPreference.balanced,
    InspectionReading<AssistantDeviceCapabilities>? host,
    RuntimeCompatibility? support,
    List<VerifiedInstalledModel> installed = const [],
    List<ModelProfile>? catalog,
    String task = 'short_answers',
  }) => service.recommend(
    models: catalog ?? models,
    device: host ?? device(),
    runtime: support ?? runtime(),
    now: now,
    preference: preference,
    installed: installed,
    task: task,
  );

  test(
    'catalog keeps legacy display fields and verified immutable identity',
    () {
      for (final m in models) {
        expect(m.name, isNotEmpty);
        expect(m.requiredRamGb, greaterThan(0));
        expect(m.requirements, isNotNull);
        expect(
          m.downloadUrl,
          contains('/resolve/${m.requirements!.sourceRevision}/'),
        );
        expect(m.requirements!.testedConfigurations, isEmpty);
      }
      expect(ModelProfile.fromJson({'id': 'legacy'}).requirements, isNull);
      final broken = Map<String, dynamic>.from(raw.first as Map);
      broken['requirements'] = {'bytes': 1, 'sha256': 'fake'};
      expect(ModelProfile.fromJson(broken).requirements, isNull);
    },
  );
  test('preferences rank deterministically and give a smaller fallback', () {
    expect(result().recommended!.model.id, models[1].id);
    expect(
      result(preference: ModelPreference.speed).recommended!.model.id,
      models[0].id,
    );
    final quality = result(
      preference: ModelPreference.quality,
      task: 'reasoning',
    );
    expect(quality.recommended!.model.id, models[2].id);
    expect(quality.smallerFallback!.model.id, models[1].id);
    expect(
      result(catalog: models.reversed.toList()).recommended!.model.id,
      models[1].id,
    );
  });
  test(
    'unknown/missing/stale/future runtime never produces a recommendation',
    () {
      for (final r in [
        runtime(available: null),
        runtime(available: false),
        runtime(readAt: now.subtract(const Duration(minutes: 1))),
        runtime(readAt: now.add(const Duration(seconds: 1))),
        runtime(supported: {}),
        runtime(platform: AssistantHostPlatform.android),
      ]) {
        expect(result(support: r).recommended, isNull);
      }
    },
  );
  test('unknown/stale/failed metrics never produce a recommendation', () {
    for (final d in [
      device(memory: null),
      device(disk: null),
      device(readAt: now.subtract(const Duration(minutes: 1))),
      device(readAt: now.add(const Duration(seconds: 1))),
      device(status: InspectionStatus.failed),
    ]) {
      expect(result(host: d).recommended, isNull);
    }
  });
  test(
    'budget includes weights, runtime, context and host reserve at boundary',
    () {
      final m = models.first;
      final required =
          m.requirements!.estimatedMemoryBytes + service.memoryReserveBytes;
      final exact = required / 1073741824;
      expect(
        result(host: device(memory: exact), catalog: [m]).recommended,
        isNotNull,
      );
      expect(
        result(
          host: device(memory: (required - 1) / 1073741824),
          catalog: [m],
        ).recommended,
        isNull,
      );
      expect(result(host: device(memory: 0)).recommended, isNull);
    },
  );
  test('download needs disk reserve unless installed identity is verified', () {
    final m = models.first;
    final r = m.requirements!;
    final installed = VerifiedInstalledModel(
      id: m.id,
      sha256: r.sha256,
      bytes: r.bytes,
    );
    expect(result(host: device(disk: 0), catalog: [m]).recommended, isNull);
    final reused =
        result(
          host: device(disk: 0),
          catalog: [m],
          installed: [installed],
        ).recommended!;
    expect(reused.reuseInstalled, isTrue);
    expect(reused.toJson()['downloadBytes'], 0);
    expect(
      result(
        host: device(disk: 0),
        catalog: [m],
        installed: [
          VerifiedInstalledModel(id: m.id, sha256: 'wrong', bytes: r.bytes),
        ],
      ).recommended,
      isNull,
    );
    expect(
      result(
        host: device(disk: 0),
        catalog: [m],
        installed: [
          VerifiedInstalledModel(
            id: m.id,
            sha256: r.sha256,
            bytes: r.bytes - 1,
          ),
        ],
      ).recommended,
      isNull,
    );
  });
  test('unsupported format and absent catalog metadata remain blocked', () {
    final broken = Map<String, dynamic>.from(raw.first as Map);
    broken['requirements'] = {
      ...Map<String, dynamic>.from(broken['requirements'] as Map),
      'format': 'safetensors',
    };
    expect(
      result(
        catalog: [ModelProfile.fromJson(broken)],
      ).candidates.single.blockers,
      contains('format_unsupported'),
    );
    expect(
      result(
        catalog: [
          ModelProfile.fromJson({'id': 'custom'}),
        ],
      ).recommended,
      isNull,
    );
  });
  test('serialized estimates do not claim measured performance', () {
    final data = result().recommended!.toJson();
    expect(data['performanceVerified'], isFalse);
    expect(data['estimateKind'], 'conservative_budget_not_benchmark');
    expect(() => jsonEncode(data), returnsNormally);
  });
}
