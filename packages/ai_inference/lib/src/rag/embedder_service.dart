// embedder_service.dart: manages the Qwen3-Embedding GGUF for rag_v3.
//
// Responsibilities:
//  - load the embedder GGUF as a dedicated LlamaEngine instance so the chat
//    model's context/KV is never disturbed
//  - embed queries + the 10 red-flag anchor queries once at load
//  - degrade gracefully: isReady=false => callers fall back to LegacyRag
//
// Download: ModelStore handles first-run acquisition (same pattern as the
// chat model); this service only consumes a local file path.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'package:ai_inference/src/rag/red_flag_triage.dart';
import 'package:ai_inference/src/rag/rag_service.dart';

class EmbedderService {
  EmbedderService._();
  static final EmbedderService instance = EmbedderService._();

  // File name contract: the app's known-models registry (apps/rescate_app/
  // lib/features/ai_chat/state/known_models.dart) downloads the embedder
  // under EXACTLY this name; download and load resolve through the same
  // constant so they can never diverge (review item #5).
  static const String kEmbedderFile = 'qwen3-embedding-0.6b-q5km.gguf';
  static const int kExpectedDim = 1024;

  LlamaEngine? _engine;
  bool _ready = false;
  int _dim = 0;

  bool get isReady => _ready;

  /// Loads the embedder from [modelPath] (a local GGUF file).
  ///
  /// Dedicated engine: embeddings only, tiny context, CPU threads, no GPU
  /// layers (the chat model owns the GPU budget).
  Future<bool> load(String modelPath) async {
    if (_ready) return true;
    try {
      final engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: 512,
          batchSize: 512,
          gpuLayers: 0,
          numberOfThreads: 2,
        ),
      );
      // smoke-test: embed a probe string, check dimension
      final v = await engine.embed('rescate probe');
      if (v.isEmpty) {
        debugPrint('EmbedderService: probe returned empty vector');
        return false;
      }
      _dim = v.length;
      _engine = engine;
      _ready = true;
      debugPrint('EmbedderService: ready (dim=$_dim)');
      await _embedAnchors();
      return true;
    } catch (e) {
      debugPrint('EmbedderService: load failed: $e');
      _engine = null;
      _ready = false;
      return false;
    }
  }

  /// Embed [text]; returns null when the embedder is not ready.
  Future<List<double>?> embed(String text) async {
    if (!_ready || _engine == null) return null;
    try {
      final v = await _engine!.embed(text);
      if (v.length != kExpectedDim) {
        debugPrint(
          'EmbedderService: unexpected dim ${v.length} (want $kExpectedDim)',
        );
      }
      return v;
    } catch (e) {
      debugPrint('EmbedderService: embed failed: $e');
      _ready = false; // a failure here means the engine is unusable
      return null;
    }
  }

  /// Embeds all red-flag anchor queries once and registers them with the
  /// RagService, enabling force-injection for triaged queries.
  Future<void> _embedAnchors() async {
    for (final flag in kRedFlags) {
      final v = await embed(flag.anchorQuery);
      if (v != null) {
        RagService.instance.registerAnchorVector(flag.id, v);
      }
    }
    debugPrint('EmbedderService: ${kRedFlags.length} anchor vectors registered');
  }

  /// Where the embedder GGUF lives (app-private models dir).
  static String embedderPath(String modelsDir) => '$modelsDir/$kEmbedderFile';

  static bool exists(String modelsDir) =>
      File(embedderPath(modelsDir)).existsSync();

  void dispose() {
    try {
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _ready = false;
  }
}
