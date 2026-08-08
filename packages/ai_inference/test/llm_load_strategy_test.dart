// packages/ai_inference/test/llm_load_strategy_test.dart

import 'package:ai_inference/ai_inference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('buildFallbackLadder', () {
    test('returns five rungs in decreasing aggressiveness for a normal device',
        () {
      final ladder = buildFallbackLadder(DeviceProfile.fallback);
      expect(ladder, hasLength(5));

      // Rung 0 — historical defaults
      expect(ladder[0].params.preferredBackend, GpuBackend.vulkan);
      expect(ladder[0].params.gpuLayers, greaterThan(100));
      expect(ladder[0].params.useMlock, isTrue);

      // Rung 1 — vulkan all-layers but mlock off and q8_0 KV
      expect(ladder[1].params.preferredBackend, GpuBackend.vulkan);
      expect(ladder[1].params.useMlock, isFalse);
      expect(ladder[1].params.cacheTypeK, KvCacheType.q8_0);

      // Rung 2 — partial GPU offload
      expect(ladder[2].params.preferredBackend, GpuBackend.vulkan);
      expect(ladder[2].params.gpuLayers, lessThan(100));

      // Rung 3 — CPU-only with q8_0. Context must fit a real turn (~700-token
      // prompt + up to 1024 generated tokens), and batching must not be
      // throttled: this rung is the primary path on slow-Vulkan SoCs.
      expect(ladder[3].params.preferredBackend, GpuBackend.cpu);
      expect(ladder[3].params.gpuLayers, 0);
      expect(ladder[3].params.cacheTypeK, KvCacheType.q8_0);
      expect(ladder[3].params.contextSize, greaterThanOrEqualTo(2048));
      expect(ladder[3].params.batchSize, 256);

      // Rung 4 — last-ditch CPU with q4_0
      expect(ladder[4].params.preferredBackend, GpuBackend.cpu);
      expect(ladder[4].params.cacheTypeK, KvCacheType.q4_0);
    });

    test('low-RAM profile disables mlock at rung 0', () {
      const profile = DeviceProfile(
        cores: 4,
        bigCores: 2,
        recommendedThreads: 3,
        recommendedBatchThreads: 3,
        totalRamMb: 2048,
        availRamMb: 1024,
        isLowRam: true,
        recommendedGpuLayers: 999,
        recommendedContextSize: 2048,
        recommendedBatchSize: 256,
        recommendedMicroBatchSize: 128,
        cacheTypeK: 'q8_0',
        cacheTypeV: 'q8_0',
        socModel: 'test',
      );
      final ladder = buildFallbackLadder(profile);
      expect(ladder[0].params.useMlock, isFalse);
      expect(ladder[0].params.cacheTypeK, KvCacheType.q8_0);
    });
  });

  group('safeModeRungIndex', () {
    test('points at the first CPU-only rung', () {
      final ladder = buildFallbackLadder(DeviceProfile.fallback);
      expect(ladder[safeModeRungIndex].params.preferredBackend, GpuBackend.cpu);
    });

    test('firstCpuRungIndex agrees with the constant on a full ladder', () {
      final ladder = buildFallbackLadder(DeviceProfile.fallback);
      expect(firstCpuRungIndex(ladder), safeModeRungIndex);
    });
  });

  group('slow-Vulkan SoC handling', () {
    DeviceProfile profileFor(String soc) => DeviceProfile(
          cores: 8,
          bigCores: 2,
          recommendedThreads: 2,
          recommendedBatchThreads: 6,
          totalRamMb: 7651,
          availRamMb: 3216,
          isLowRam: false,
          recommendedGpuLayers: 999,
          recommendedContextSize: 4096,
          recommendedBatchSize: 256,
          recommendedMicroBatchSize: 128,
          cacheTypeK: 'f16',
          cacheTypeV: 'f16',
          socModel: soc,
        );

    test('hasSlowVulkanCompute matches known parts case-insensitively', () {
      expect(hasSlowVulkanCompute('MT6893'), isTrue);
      expect(hasSlowVulkanCompute('mt6893'), isTrue);
      expect(hasSlowVulkanCompute('SM8650'), isFalse);
      expect(hasSlowVulkanCompute(''), isFalse);
    });

    test('MT6893 ladder is CPU-only — no Vulkan rungs at all', () {
      final ladder = buildFallbackLadder(profileFor('MT6893'));
      expect(ladder, isNotEmpty);
      for (final rung in ladder) {
        expect(rung.params.preferredBackend, GpuBackend.cpu);
        expect(rung.params.gpuLayers, 0);
      }
    });

    test('slow-Vulkan ladder starts on a usable context and batch size', () {
      final ladder = buildFallbackLadder(profileFor('MT6893'));
      expect(ladder.first.params.contextSize, greaterThanOrEqualTo(2048));
      expect(ladder.first.params.batchSize, 256);
    });

    test('firstCpuRungIndex is 0 for an already-CPU-only ladder', () {
      final ladder = buildFallbackLadder(profileFor('MT6893'));
      // Guards the crash-collapse / low-RAM jumps: using the literal
      // safeModeRungIndex here would index past the end of this ladder.
      expect(firstCpuRungIndex(ladder), 0);
      expect(safeModeRungIndex, greaterThanOrEqualTo(ladder.length));
    });

    test('unaffected SoCs keep the full five-rung ladder', () {
      final ladder = buildFallbackLadder(profileFor('SM8650'));
      expect(ladder, hasLength(5));
      expect(ladder.first.params.preferredBackend, GpuBackend.vulkan);
    });
  });

  group('LoadAttempt', () {
    test('nextRungAfterCrash is one past the crashed rung', () {
      const attempt = LoadAttempt(
        rung: 1,
        modelPath: '/x.gguf',
        timestampMs: 0,
      );
      expect(attempt.nextRungAfterCrash, 2);
    });

    test('JSON round-trip preserves all fields', () {
      const attempt = LoadAttempt(
        rung: 3,
        modelPath: '/data/model.gguf',
        timestampMs: 1234567890,
        note: 'safe mode',
      );
      final restored = LoadAttempt.fromJson(attempt.toJson());
      expect(restored, isNotNull);
      expect(restored!.rung, 3);
      expect(restored.modelPath, '/data/model.gguf');
      expect(restored.timestampMs, 1234567890);
      expect(restored.note, 'safe mode');
    });

    test('fromJson rejects malformed maps', () {
      expect(LoadAttempt.fromJson(<String, Object?>{}), isNull);
      expect(
        LoadAttempt.fromJson(<String, Object?>{'rung': 1}),
        isNull,
      );
    });

    test('crashedOnGpuBackend is true for vulkan and false for cpu', () {
      const vulkan = LoadAttempt(
        rung: 1,
        modelPath: '/x.gguf',
        timestampMs: 0,
        backend: 'vulkan',
      );
      const cpu = LoadAttempt(
        rung: 3,
        modelPath: '/x.gguf',
        timestampMs: 0,
        backend: 'cpu',
      );
      const legacy = LoadAttempt(
        rung: 0,
        modelPath: '/x.gguf',
        timestampMs: 0,
      );
      expect(vulkan.crashedOnGpuBackend, isTrue);
      expect(cpu.crashedOnGpuBackend, isFalse);
      // Legacy markers (no backend field) must default to false so we don't
      // incorrectly skip rungs for users upgrading from the prior build.
      expect(legacy.crashedOnGpuBackend, isFalse);
    });

    test('JSON round-trip preserves backend', () {
      const attempt = LoadAttempt(
        rung: 2,
        modelPath: '/m.gguf',
        timestampMs: 1,
        backend: 'vulkan',
      );
      final restored = LoadAttempt.fromJson(attempt.toJson());
      expect(restored?.backend, 'vulkan');
    });
  });
}
