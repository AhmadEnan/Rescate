// packages/ai_inference/lib/src/llm_config.dart

import 'package:llamadart/llamadart.dart';

/// Default hardware configuration for llamadart inference.
class LlmDefaults {
  const LlmDefaults._();

  static const int nThreads = 4;
  static const int nGpuLayers = 99; // Set to 99 to offload all possible layers to the GPU
  static const int contextSize = 2048;
  static const int batchSize = 512;

  static const double temperature = 0.05;
  static const double topP = 0.95;
  static const int topK = 40;
  static const int maxTokens = 350;
  static const double repeatPenalty = 1.1;

  /// Builds a [ModelParams] from the default settings above.
  static ModelParams buildModelParams() => const ModelParams(
        contextSize: contextSize,
        gpuLayers: nGpuLayers,
        preferredBackend: GpuBackend.auto, // Let llama.cpp auto-detect the best backend for the Android device
        batchSize: batchSize,
        microBatchSize: batchSize,
        numberOfThreads: nThreads,
        numberOfThreadsBatch: nThreads,
      );
}

// ── System Prompts ────────────────────────────────────────────────────────────
// System prompts and prompt building are now handled by LegacyRag in legacy_rag.dart.
