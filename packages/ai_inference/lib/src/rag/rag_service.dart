// rag_service.dart: async facade over rag_v3 exposing the same call shape the
// app already uses (LegacyRag.search + LegacyRag.buildPrompt), so LlmService
// can switch implementations without touching call sites' structure.
//
// Embedding: the query is embedded with the llamadart engine's embed()
// (Qwen3-Embedding GGUF). While the embedder is absent, falls back to
// LegacyRag (term-map lexical) so the app never blocks on the download.
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'rag_assets.dart';
import 'rag_v3.dart';
import 'red_flag_triage.dart';
import 'triage_context.dart';
import 'prompt_v3.dart';
import '../legacy_rag.dart';

class RagService {
  RagService._();
  static final RagService instance = RagService._();

  RagV3WithTriage? _rag;
  RagAssets? _assets;
  final Map<String, Float32List> _anchorVecs = {};
  bool _loaded = false;

  bool get isReady => _loaded && _rag != null;

  /// Load rag assets at startup (cheap: file reads + parsing only).
  Future<void> loadAssets() async {
    if (_loaded) return;
    try {
      _assets = await RagAssets.load();
      _rag = RagV3WithTriage(RagV3(_assets!));
      _loaded = true;
      for (final f in kRedFlags) {
        _anchorVecs[f.id]; // registry key pre-created; vec filled by embedder
      }
    } catch (e) {
      debugPrint('RagService: asset load failed, staying on LegacyRag: $e');
      _loaded = false;
    }
  }

  /// Register the anchor vector for a flag after embedding its anchor query.
  void registerAnchorVector(String flagId, List<double> vec) {
    final v = Float32List(vec.length);
    for (var i = 0; i < vec.length; i++) {
      v[i] = vec[i];
    }
    _anchorVecs[flagId] = v;
    _rag?.rag; // rag instance holds no anchor state; registry is local
  }

  /// Anchor query vector lookup used by [buildPromptV3]'s force-injection.
  Float32List? anchorVector(String flagId) => _anchorVecs[flagId];

  bool get anchorsReady =>
      kRedFlags.every((f) => _anchorVecs.containsKey(f.id));

  /// Embed via the app's llamadart engine (injected to avoid a hard dep here).
  final Future<List<double>> Function(String text)? embedText = null;

  /// Full search+context. [queryVec] is the embedded user query; when null
  /// (embedder unavailable) falls back to LegacyRag lexical retrieval.
  Future<({String prompt, List<String> sources, bool triaged})> buildPromptV3({
    required String question,
    required Float32List? queryVec,
    String? toolDeclarations,
    bool enableThinking = false,
  }) async {
    final arabic = question.runes.any((c) => c >= 0x0600 && c <= 0x06FF);

    if (isReady && queryVec != null) {
      final ctx = _rag!.buildContext(queryVec, question);
      final prompt = buildGemmaPromptV3(
        context: ctx.contextWithFrame,
        question: question,
        arabic: arabic,
      );
      return (
        prompt: prompt,
        sources: ctx.base.sources,
        triaged: ctx.hasRedFlag,
      );
    }

    // Fallback: legacy lexical path (validated, ships in every build).
    final chunks = LegacyRag.search(question, topK: 5);
    final legacyPrompt = LegacyRag.buildPrompt(
      question: question,
      chunks: chunks,
      toolDeclarations: toolDeclarations,
      enableThinking: enableThinking,
    );
    return (
      prompt: legacyPrompt,
      sources: chunks.map((c) => c['source'] as String).toList(),
      triaged: false,
    );
  }

  /// Triage-only check (used by UI to show an emergency banner if desired).
  bool hasRedFlag(String question) => triageQuery(question).isNotEmpty;
}
