// rag_v3 context assembly with triage integration.
//
// Wraps RagV3: on a triage hit, force-injects the flag's emergency guidance
// (retrieved via a clinical-English anchor query) into the context ahead of
// budget cuts and prepends the escalation frame to the user message.
import 'dart:typed_data';

import 'rag_v3.dart';
import 'red_flag_triage.dart';

class TriageAugmentedContext {
  final RagV3Context base;
  final List<TriageHit> triageHits;
  final List<String> injectedSources;
  final String escalationFrame;

  TriageAugmentedContext({
    required this.base,
    required this.triageHits,
    required this.injectedSources,
    required this.escalationFrame,
  });

  bool get hasRedFlag => triageHits.isNotEmpty;

  /// Final user-side context block (frame + context).
  String get contextWithFrame => hasRedFlag
      ? '$escalationFrame\n\n${base.context}'
      : base.context;
}

class RagV3WithTriage {
  final RagV3 rag;
  RagV3WithTriage(this.rag);

  TriageAugmentedContext buildContext(
    Float32List queryVec,
    String rawQuery, {
    int topK = 16,
    int maxTokens = 1400,
    int neighbors = 1,
  }) {
    final hits = triageQuery(rawQuery);
    final base = rag.buildContext(
      queryVec,
      topK: topK,
      maxTokens: hits.isEmpty ? maxTokens : (maxTokens * 0.65).toInt(),
      neighbors: neighbors,
    );
    if (hits.isEmpty) {
      return TriageAugmentedContext(
        base: base,
        triageHits: const [],
        injectedSources: const [],
        escalationFrame: '',
      );
    }

    final arabic = rawQuery.runes.any((c) => c >= 0x0600 && c <= 0x06FF);
    final injectedSources = <String>[];
    final seenSources = base.sources.toSet();
    final injectedHits = <RagHit>[];
    var injectedTokens = 0;
    final reserve = (maxTokens * 0.35).toInt();

    for (final h in hits) {
      // Force-inject the flag's emergency guidance via its precomputed anchor
      // vector. An unregistered anchor (embedder still loading) degrades to
      // base retrieval — the escalation frame still fires either way.
      try {
        final actx = rag.buildContext(
          _anchorVec(h.flag.id),
          topK: 6,
          maxTokens: reserve - injectedTokens,
          neighbors: 0,
        );
        for (final unit in actx.hits) {
          if (seenSources.contains(unit.sentence.source)) continue;
          final cost = unit.sentence.text.length / 3.7 + 12;
          if (injectedTokens + cost > reserve) break;
          seenSources.add(unit.sentence.source);
          injectedTokens += cost.toInt();
          injectedSources.add(unit.sentence.source);
          injectedHits.add(unit);
        }
      } on _AnchorNotRegistered {
        continue;
      }
    }

    final merged = RagV3Context(
      hits: [...injectedHits, ...base.hits],
      context: injectedHits.isEmpty
          ? base.context
          : [
              for (var i = 0; i < injectedHits.length; i++)
                '- ${injectedHits[i].sentence.text} [T${i + 1}]',
              base.context,
            ].join('\n'),
      sources: [...injectedSources, ...base.sources],
      tokensEst: base.tokensEst + injectedTokens,
    );

    return TriageAugmentedContext(
      base: merged,
      triageHits: hits,
      injectedSources: injectedSources,
      escalationFrame: escalationFrame(hits, arabic),
    );
  }

  // Anchor vectors are precomputed at app start by embedding the anchor
  // queries with the embedder; this registry is filled by the service layer.
  final Map<String, Float32List> _anchorVecCache = {};

  void registerAnchorVec(String flagId, Float32List vec) =>
      _anchorVecCache[flagId] = vec;

  Float32List _anchorVec(String flagId) {
    final v = _anchorVecCache[flagId];
    if (v == null) {
      // Graceful degradation: an unregistered anchor (embedder still loading,
      // or a new flag added without re-embedding) must NEVER crash a triage
      // turn. Skip force-injection for this flag; base retrieval + the
      // escalation frame still fire, so the emergency is not dropped.
      throw _AnchorNotRegistered(flagId);
    }
    return v;
  }
}

/// Internal: anchor vector not yet registered for a flag.
class _AnchorNotRegistered implements Exception {
  final String flagId;
  _AnchorNotRegistered(this.flagId);
  @override
  String toString() =>
      'anchor vec for $flagId not registered - embed the anchor queries at startup';
}
