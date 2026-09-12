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
import '../legacy_rag.dart' as legacy;

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
      // Anchor vectors are filled by registerAnchorVector once the embedder
      // is up (see EmbedderService.load); triage force-injection degrades to
      // base retrieval until every flag has its vector.
    } catch (e) {
      debugPrint('RagService: asset load failed, staying on LegacyRag: $e');
      _loaded = false;
    }
  }

  /// Register the anchor vector for a flag after embedding its anchor query.
  ///
  /// Delegates to the [RagV3WithTriage] instance itself — it owns the anchor
  /// registry its buildContext force-injection reads from. The service-side
  /// mirror below is kept only for `anchorsReady` reporting; the two maps
  /// must never diverge (this was the P0 wiring bug in review: the service
  /// filled its own map while triage read an empty cache and threw).
  void registerAnchorVector(String flagId, List<double> vec) {
    final v = Float32List(vec.length);
    for (var i = 0; i < vec.length; i++) {
      v[i] = vec[i];
    }
    _anchorVecs[flagId] = v;
    _rag?.registerAnchorVec(flagId, v);
  }

  /// Anchor query vector lookup used by [buildPromptV3]'s force-injection.
  Float32List? anchorVector(String flagId) => _anchorVecs[flagId];

  bool get anchorsReady =>
      kRedFlags.every((f) => _anchorVecs.containsKey(f.id));

  // ---- test-only surface (review-required wiring tests) -------------------

  /// Build a service around a caller-supplied [RagV3WithTriage] so anchor
  /// wiring can be tested without a live embedder.
  factory RagService.forTest(RagV3WithTriage rag) {
    final svc = RagService._();
    svc._rag = rag;
    svc._loaded = true;
    return svc;
  }

  /// Test hook: expose buildContext on the service's triage instance.
  TriageAugmentedContext buildContextForTest(
    Float32List queryVec,
    String rawQuery,
  ) =>
      _rag!.buildContext(queryVec, rawQuery);

  /// Test hook: expose the v3 prompt build without touching the singleton.
  /// [queryVec] may be null — that forces the fallback path, which round-2
  /// tests exercise (fallback triage).
  ({String prompt, List<String> sources, bool triaged}) buildPromptForTest({
    required String question,
    required Float32List? queryVec,
    String? toolDeclarations,
    bool enableThinking = false,
  }) {
    final arabic = question.runes.any((c) => c >= 0x0600 && c <= 0x06FF);
    if (queryVec == null || !isReady) {
      // Fallback path (same as buildPromptV3's fallback branch).
      final chunks = legacy.LegacyRag.search(question, topK: 5);
      final legacyPrompt = legacy.LegacyRag.buildPrompt(
        question: question,
        chunks: chunks,
        toolDeclarations: toolDeclarations,
        enableThinking: enableThinking,
      );
      final fallbackHits = triageQuery(question);
      final fallbackFrame = fallbackHits.isEmpty
          ? ''
          : escalationFrame(fallbackHits, arabic);
      final promptWithFrame = fallbackFrame.isEmpty
          ? legacyPrompt
          : legacyPrompt.replaceFirst(
              '<|turn>user\n',
              '<|turn>user\n$fallbackFrame\n\n',
            );
      return (
        prompt: promptWithFrame,
        sources: chunks.map((c) => c['source'] as String).toList(),
        triaged: fallbackHits.isNotEmpty,
      );
    }
    final ctx = _rag!.buildContext(queryVec, question);
    final prompt = buildGemmaPromptV3(
      context: ctx.contextWithFrame,
      question: question,
      arabic: arabic,
      toolDeclarations: toolDeclarations,
      enableThinking: enableThinking,
    );
    return (
      prompt: prompt,
      sources: ctx.base.sources,
      triaged: ctx.hasRedFlag,
    );
  }

  /// Full search+context. [queryVec] is the embedded user query; when null
  /// (embedder unavailable) falls back to LegacyRag lexical retrieval.
  ///
  /// [contextTokenBudget] caps the retrieved-context size. Retrieved text
  /// dominates CPU prefill and time-to-first-token scales ~linearly with
  /// prompt tokens, so callers pass a device-aware budget (see LlmService).
  /// Null keeps the current default (1400) that the eval suite validated.
  Future<({String prompt, List<String> sources, bool triaged})> buildPromptV3({
    required String question,
    required Float32List? queryVec,
    String? toolDeclarations,
    bool enableThinking = false,
    int? contextTokenBudget,
  }) async {
    final arabic = question.runes.any((c) => c >= 0x0600 && c <= 0x06FF);

    if (isReady && queryVec != null) {
      final ctx = _rag!.buildContext(
        queryVec,
        question,
        maxTokens: contextTokenBudget ?? 1400,
      );
      final prompt = buildGemmaPromptV3(
        context: ctx.contextWithFrame,
        question: question,
        arabic: arabic,
        // Tool schemas must survive the v3 path — tool-enabled turns lose
        // their declarations otherwise (review item #4).
        toolDeclarations: toolDeclarations,
        enableThinking: enableThinking,
      );
      return (
        prompt: prompt,
        sources: ctx.base.sources,
        triaged: ctx.hasRedFlag,
      );
    }

    // Fallback: legacy lexical path (validated, ships in every build).
    // Triage still runs here — it is pure string matching and needs no
    // embedder. A fresh install asking about stroke signs MUST get the
    // escalation frame even before the embedder downloads (review round 2).
    final chunks = legacy.LegacyRag.search(question, topK: 5);
    final legacyPrompt = legacy.LegacyRag.buildPrompt(
      question: question,
      chunks: chunks,
      toolDeclarations: toolDeclarations,
      enableThinking: enableThinking,
    );
    final fallbackHits = triageQuery(question);
    final fallbackFrame = fallbackHits.isEmpty
        ? ''
        : escalationFrame(fallbackHits, arabic);
    final promptWithFrame = fallbackFrame.isEmpty
        ? legacyPrompt
        : legacyPrompt.replaceFirst(
            '<|turn>user\n',
            '<|turn>user\n$fallbackFrame\n\n',
          );
    return (
      prompt: promptWithFrame,
      sources: chunks.map((c) => c['source'] as String).toList(),
      triaged: fallbackHits.isNotEmpty,
    );
  }

  /// Triage-only check (used by UI to show an emergency banner if desired).
  bool hasRedFlag(String question) => triageQuery(question).isNotEmpty;
}
