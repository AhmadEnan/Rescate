// packages/ai_inference/lib/src/llm_load_strategy.dart

import 'package:llamadart/llamadart.dart';

import 'device_profile.dart';

/// One step in the GGUF model load fallback ladder.
///
/// Each rung represents a progressively safer (but slower / lower-quality)
/// configuration. The loader walks the ladder from index 0 downward until a
/// rung succeeds or every rung has failed.
///
/// `description` is intended for log/UI output and must not be parsed by code.
class LlmLoadRung {
  const LlmLoadRung({required this.description, required this.params});

  final String description;
  final ModelParams params;
}

/// Builds an ordered fallback ladder of [LlmLoadRung]s, most-aggressive first.
///
/// Rung 0 mirrors the historical defaults (full Vulkan offload, mlock on for
/// non-low-RAM devices, f16 KV cache). Each subsequent rung relaxes one
/// dimension at a time:
///
/// - Rung 1: drop mlock, drop KV cache to q8_0, halve n_ctx.
/// - Rung 2: partial Vulkan offload (16 layers) so weights stay in system RAM.
/// - Rung 3: CPU-only, q8_0 KV, n_ctx 1024.
/// - Rung 4: CPU-only, q4_0 KV, n_ctx 1024 — last-ditch.
List<LlmLoadRung> buildFallbackLadder(DeviceProfile profile) {
  final bool isLowRam = profile.isLowRam;
  final int aggressiveCtx = profile.recommendedContextSize;
  final int safeCtx = isLowRam ? 1024 : 2048;
  final KvCacheType aggressiveKv = _parseKv(profile.cacheTypeK);

  final ModelParams rung0 = ModelParams(
    contextSize: aggressiveCtx,
    gpuLayers: profile.recommendedGpuLayers,
    preferredBackend: GpuBackend.vulkan,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: profile.recommendedBatchSize,
    microBatchSize: profile.recommendedMicroBatchSize,
    useMmap: true,
    useMlock: !isLowRam,
    cacheTypeK: aggressiveKv,
    cacheTypeV: aggressiveKv,
  );

  final ModelParams rung1 = ModelParams(
    contextSize: safeCtx,
    gpuLayers: 999,
    preferredBackend: GpuBackend.vulkan,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: 128,
    microBatchSize: 64,
    useMmap: true,
    useMlock: false,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
  );

  final ModelParams rung2 = ModelParams(
    contextSize: safeCtx,
    gpuLayers: 16,
    preferredBackend: GpuBackend.vulkan,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: 128,
    microBatchSize: 64,
    useMmap: true,
    useMlock: false,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
  );

  final ModelParams rung3 = ModelParams(
    contextSize: 1024,
    gpuLayers: 0,
    preferredBackend: GpuBackend.cpu,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: 64,
    microBatchSize: 32,
    useMmap: true,
    useMlock: false,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
  );

  final ModelParams rung4 = ModelParams(
    contextSize: 1024,
    gpuLayers: 0,
    preferredBackend: GpuBackend.cpu,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: 32,
    microBatchSize: 16,
    useMmap: true,
    useMlock: false,
    cacheTypeK: KvCacheType.q4_0,
    cacheTypeV: KvCacheType.q4_0,
  );

  return <LlmLoadRung>[
    LlmLoadRung(
      description:
          'rung0/default: vulkan all-layers mlock=${!isLowRam} kv=$aggressiveKv ctx=$aggressiveCtx',
      params: rung0,
    ),
    LlmLoadRung(
      description: 'rung1/vulkan-safe: vulkan all-layers mlock=false kv=q8_0 ctx=$safeCtx',
      params: rung1,
    ),
    LlmLoadRung(
      description: 'rung2/vulkan-partial: vulkan 16-layers mlock=false kv=q8_0 ctx=$safeCtx',
      params: rung2,
    ),
    LlmLoadRung(
      description: 'rung3/cpu: cpu mlock=false kv=q8_0 ctx=1024',
      params: rung3,
    ),
    LlmLoadRung(
      description: 'rung4/cpu-q4: cpu mlock=false kv=q4_0 ctx=1024',
      params: rung4,
    ),
  ];
}

/// Rung index used by the model-setup screen "Safe mode" toggle to force the
/// CPU-only configuration directly.
const int safeModeRungIndex = 3;

KvCacheType _parseKv(String value) {
  switch (value) {
    case 'q8_0':
      return KvCacheType.q8_0;
    case 'q4_0':
      return KvCacheType.q4_0;
    case 'f16':
    default:
      return KvCacheType.f16;
  }
}

/// Human-readable summary of a [ModelParams] for log lines.
String describeModelParams(ModelParams p) {
  return 'backend=${p.preferredBackend.name} gpuLayers=${p.gpuLayers} '
      'ctx=${p.contextSize} batch=${p.batchSize}/${p.microBatchSize} '
      'mlock=${p.useMlock} mmap=${p.useMmap} '
      'kv=${p.cacheTypeK.name}/${p.cacheTypeV.name} '
      'threads=${p.numberOfThreads}/${p.numberOfThreadsBatch}';
}
