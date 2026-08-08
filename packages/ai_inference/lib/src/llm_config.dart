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

  /// Whether to enable Gemma 4's hidden reasoning channel.
  ///
  /// Disabled by default. Profiling on an MT6893 showed hidden thought tokens
  /// outnumbering visible answer tokens ~3:1, and at ~1.5 tok/s decode that
  /// reasoning is pure latency before the user sees any first-aid instruction.
  /// In an emergency, time-to-useful-text matters more than answer polish.
  static bool enableThinking = false;

  // Sampling defaults — sourced from Unsloth Studio tuning, then adjusted
  // for Rescate's on-device deployment profile.
  static const double temperature = 1.0;
  static const double topP = 0.95;
  static const int topK = 64;
  static const double minP = 0.0;
  // Max Tokens: realistic hard cap on response length. The previous value
  // (131072) was inherited from the Unsloth "context window" setting but the
  // actual loaded context is 4096 (see buildFallbackLadder rung 0), so a 128k
  // decode cap was meaningless and risked runaway decoding past EOS at
  // 2 tokens/sec. 1024 tokens is a generous single-turn answer budget and
  // bounds worst-case decode time on a slow device to ~8-10 minutes.
  static const int maxTokens = 1024;
  // Repetition Penalty: 1.1 (llamadart's own default). The previous value of
  // 1.0 disabled penalty entirely, which combined with temp=1.0 and no stop
  // sequences produced visible repetition loops in long answers — expensive
  // at single-digit tokens/sec.
  static const double repeatPenalty = 1.1;
  // Stop sequences: emit the Gemma 4 end-of-turn marker so libllama halts
  // cleanly instead of generating past the turn boundary into noise that the
  // channel splitter then has to discard. Picked from the Gemma 4 chat
  // template used by LegacyRag.buildPrompt (`legacy_rag.dart`).
  static const List<String> stopSequences = <String>['<turn|>'];
  // Forced context length (Unsloth Studio "Context Length" slider).
  // NOTE: this is currently DEAD CODE on the production load path —
  // LlmService.loadModel uses buildFallbackLadder's rung params instead of
  // buildModelParams(). Kept for direct callers/tests.
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
