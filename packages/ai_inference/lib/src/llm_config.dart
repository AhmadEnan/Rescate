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

  /// Whether GPU (Vulkan) offload is enabled. App startup sets this from
  /// SharedPreferences (`ai_chat.use_gpu`), falling back to an SoC-based
  /// default that disables GPU on known-buggy budget Mali/MediaTek chips.
  static bool useGpu = true;

  // Sampling defaults — sourced from Unsloth Studio tuning.
  static const double temperature = 1.0;
  static const double topP = 0.95;
  static const int topK = 64;
  static const double minP = 0.0;
  // Max Tokens = "Max" in Unsloth Studio → cap at the full context window.
  static const int maxTokens = 131072;
  // Repetition Penalty: Off (1.0 = no penalty).
  static const double repeatPenalty = 1.0;
  // Forced context length (Unsloth Studio "Context Length" slider).
  static const int forcedContextSize = 131072;

  /// Builds a [ModelParams] using the [activeProfile] (or fallback).
  static ModelParams buildModelParams() {
    final DeviceProfile profile = activeProfile ?? DeviceProfile.fallback;
    final gpuEnabled = useGpu && !profile.isLowRam;
    final backend = gpuEnabled ? GpuBackend.vulkan : GpuBackend.cpu;
    final gpuLayers = gpuEnabled ? profile.recommendedGpuLayers : 0;

    Profiler.event(
      'llm.backend',
      data: <String, Object?>{
        'resolved': gpuEnabled ? 'vulkan' : 'cpu',
        'threads': profile.recommendedThreads,
        'ctx': forcedContextSize,
        'gpuLayers': gpuLayers,
      },
    );

    return ModelParams(
      contextSize: forcedContextSize,
      gpuLayers: gpuLayers,
      preferredBackend: backend,
      numberOfThreads: profile.recommendedThreads,
      numberOfThreadsBatch: profile.recommendedBatchThreads,
      batchSize: profile.recommendedBatchSize,
      microBatchSize: profile.recommendedMicroBatchSize,
      useMmap: true,
      useMlock: !profile.isLowRam,
      cacheTypeK: KvCacheType.f16,
      cacheTypeV: KvCacheType.f16,
    );
  }
}

// ── System Prompts ────────────────────────────────────────────────────────────
// System prompts and prompt building are now handled by LegacyRag in legacy_rag.dart.
