// packages/ai_inference/lib/src/llm_config.dart
//
// Hardware-aware llama.cpp model parameters.
//
// On Android, llamadart 0.6.13 silently maps `GpuBackend.auto` → `cpu`, so we
// pin `GpuBackend.vulkan` explicitly. Pass these dart-defines at build time to
// enable extra Vulkan offload paths in llamadart:
//
//   --dart-define=LLAMADART_ANDROID_VULKAN_ALLOW_OP_OFFLOAD=true
//   --dart-define=LLAMADART_ANDROID_VULKAN_ALLOW_KQV=true
//   --dart-define=LLAMADART_ANDROID_VULKAN_ALLOW_FLASH_ATTN=true
//
// Call `DeviceProfile.detect()` once in app startup and assign the result to
// [LlmDefaults.activeProfile] before invoking [LlmDefaults.buildModelParams].

import 'package:dev_profiler/dev_profiler.dart';
import 'package:llamadart/llamadart.dart';

import 'device_profile.dart';

/// Default hardware configuration for llamadart inference.
class LlmDefaults {
  const LlmDefaults._();

  /// The detected device profile. App startup should set this to the result
  /// of [DeviceProfile.detect]. If left `null`, [DeviceProfile.fallback] is
  /// used instead.
  static DeviceProfile? activeProfile;

  // Sampling defaults — kept as compile-time constants.
  // 0.6 gives the model room to vary phrasing for casual or general questions
  // while staying grounded enough for emergency instructions to remain stable.
  static const double temperature = 0.6;
  static const double topP = 0.95;
  static const int topK = 40;
  static const int maxTokens = 384;
  static const double repeatPenalty = 1.1;

  /// Builds a [ModelParams] using the [activeProfile] (or fallback).
  static ModelParams buildModelParams() {
    final DeviceProfile profile = activeProfile ?? DeviceProfile.fallback;

    Profiler.event(
      'llm.backend',
      data: <String, Object?>{
        'resolved': 'vulkan',
        'threads': profile.recommendedThreads,
        'ctx': profile.recommendedContextSize,
        'gpuLayers': profile.recommendedGpuLayers,
      },
    );

    return ModelParams(
      contextSize: profile.recommendedContextSize,
      gpuLayers: profile.recommendedGpuLayers,
      preferredBackend: GpuBackend.vulkan,
      numberOfThreads: profile.recommendedThreads,
      numberOfThreadsBatch: profile.recommendedBatchThreads,
      batchSize: profile.recommendedBatchSize,
      microBatchSize: profile.recommendedMicroBatchSize,
      useMmap: true,
      useMlock: !profile.isLowRam,
      cacheTypeK: _kvCacheTypeFromString(profile.cacheTypeK),
      cacheTypeV: _kvCacheTypeFromString(profile.cacheTypeV),
    );
  }

  static KvCacheType _kvCacheTypeFromString(String value) {
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
}

// ── System Prompts ────────────────────────────────────────────────────────────
// System prompts and prompt building are now handled by LegacyRag in legacy_rag.dart.
