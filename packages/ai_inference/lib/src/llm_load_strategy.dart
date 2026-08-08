// packages/ai_inference/lib/src/llm_load_strategy.dart
//
// flashAttention is forced to `FlashAttention.enabled` on every rung. The
// upstream `auto` heuristic in llamadart only auto-enables flash attention
// when KV quantization is requested (q8_0/q4_0); for rung 0 with f16 KV it
// leaves it at `auto`, which llama.cpp historically resolves to *disabled*
// in some builds. Gemma 3/4 was designed for flash attention; the non-flash
// path costs several times the decode throughput on this architecture. We
// force it on explicitly so the choice is no longer at the mercy of the
// auto heuristic. The `LLAMADART_ANDROID_VULKAN_ALLOW_FLASH_ATTN=true`
// dart-define in `apps/rescate_app/dart_defines.json` already allowlists
// the GPU kernel, so this is the only Dart-side change needed.
//
// Note: per `ModelParams.validate()` (llamadart), non-F16 KV cache types
// require flashAttention != disabled — forcing `enabled` satisfies all rungs
// including the q8_0/q4_0 ones, so we get consistency for free.

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

/// SoC identifiers (matched as substrings against `Build.SOC_MODEL`, lowercased)
/// whose Vulkan compute path is known to be pathologically slow for llama.cpp
/// rather than outright broken.
///
/// This is a DIFFERENT failure mode from the SIGSEGV crashes the fallback
/// ladder was originally built for: the model loads fine and generates correct
/// output, but batched prefill delivers no speedup over single-token decode —
/// the signature of per-op GPU round-trips instead of real batch execution.
/// Measured on MT6893 (Dimensity 1200 / Mali-G77): prefill 2.09 tok/s vs
/// decode 1.50 tok/s, where a healthy backend shows prefill 10-100x decode.
///
/// Devices matching this list start the ladder at the CPU rung, skipping the
/// Vulkan rungs entirely. They are not crash-prone, so nothing is lost by
/// declining a GPU path that is slower than the CPU one anyway.
const List<String> slowVulkanSocMarkers = <String>[
  'mt6893', // Dimensity 1200, Mali-G77
  'mt6889', // Dimensity 1000, Mali-G77
  'mt6877', // Dimensity 900, Mali-G68
  'mt6853', // Dimensity 800U/720, Mali-G57
  'mt6785', // Helio G95, Mali-G76
  'mt6769', // Helio G8x/P65, Mali-G52
];

/// Whether [socModel] is a known slow-Vulkan part (see [slowVulkanSocMarkers]).
bool hasSlowVulkanCompute(String socModel) {
  if (socModel.isEmpty) return false;
  final String soc = socModel.toLowerCase();
  for (final String marker in slowVulkanSocMarkers) {
    if (soc.contains(marker)) return true;
  }
  return false;
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
    flashAttention: FlashAttention.enabled,
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
    flashAttention: FlashAttention.enabled,
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
    flashAttention: FlashAttention.enabled,
  );

  // Rung 3 is no longer only a last-resort crash fallback — it is the PRIMARY
  // rung for slow-Vulkan SoCs (see [hasSlowVulkanCompute]), so it is tuned for
  // throughput rather than bare survival:
  //
  // - contextSize: 1024 could not hold a real turn. Observed prompts run ~700
  //   tokens and `LlmDefaults.maxTokens` is 1024, so a 1024 window forced
  //   context truncation mid-answer. safeCtx (2048) fits prompt + answer.
  // - batchSize 64/32 throttled prefill to tiny chunks. Prefill is the
  //   dominant cost of a turn; 256/128 lets llama.cpp batch properly and is
  //   what the Vulkan rungs already used.
  final ModelParams rung3 = ModelParams(
    contextSize: safeCtx,
    gpuLayers: 0,
    preferredBackend: GpuBackend.cpu,
    numberOfThreads: profile.recommendedThreads,
    numberOfThreadsBatch: profile.recommendedBatchThreads,
    batchSize: 256,
    microBatchSize: 128,
    useMmap: true,
    useMlock: false,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
    flashAttention: FlashAttention.enabled,
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
    flashAttention: FlashAttention.enabled,
  );

  final List<LlmLoadRung> vulkanRungs = <LlmLoadRung>[
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
  ];

  final List<LlmLoadRung> cpuRungs = <LlmLoadRung>[
    LlmLoadRung(
      description: 'rung3/cpu: cpu mlock=false kv=q8_0 ctx=$safeCtx batch=256/128',
      params: rung3,
    ),
    LlmLoadRung(
      description: 'rung4/cpu-q4: cpu mlock=false kv=q4_0 ctx=1024',
      params: rung4,
    ),
  ];

  // On known slow-Vulkan SoCs the GPU rungs load successfully but run slower
  // than CPU, so the ladder would happily settle on rung 0 and never fall
  // through — the crash-driven fallback never fires for a perf problem. Drop
  // the Vulkan rungs entirely for these parts.
  if (hasSlowVulkanCompute(profile.socModel)) {
    return cpuRungs;
  }

  return <LlmLoadRung>[...vulkanRungs, ...cpuRungs];
}

/// Rung index used by the model-setup screen "Safe mode" toggle to force the
/// CPU-only configuration directly.
///
/// This is the index within the FULL ladder. Ladders built for slow-Vulkan SoCs
/// are already CPU-only and shorter, so callers must resolve the index against
/// the actual ladder via [firstCpuRungIndex] rather than using this constant
/// directly.
const int safeModeRungIndex = 3;

/// Index of the first CPU-only rung in [ladder], or 0 when the ladder is
/// already entirely CPU-only.
///
/// Use this instead of [safeModeRungIndex] whenever the value indexes into a
/// ladder that may have had its Vulkan rungs stripped.
int firstCpuRungIndex(List<LlmLoadRung> ladder) {
  for (int i = 0; i < ladder.length; i++) {
    if (ladder[i].params.preferredBackend == GpuBackend.cpu) return i;
  }
  return 0;
}

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
      'threads=${p.numberOfThreads}/${p.numberOfThreadsBatch} '
      'flashAttn=${p.flashAttention.name}';
}
