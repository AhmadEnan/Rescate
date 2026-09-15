// rag_v3: sentence-level dense retrieval for on-device use.
//
// Dart port of the validated Python pipeline (eval/rag_mirror/rag_v2.py):
//   - int8-quantized embedding matrix (7,535 x 1024)
//   - dense cosine -> top-N -> MMR diversity re-rank
//   - neighbor-sentence expansion (multi-phase instructions)
//   - whole-sentence cited context within a token budget
// BM25/RRF dropped: measured ~no contribution on the 48-case suite.
import 'dart:typed_data';

import 'rag_assets.dart';

/// Similarity floor for Latin-script queries, in cosine.
///
/// Without a floor `buildContext` always emitted topK=16 sentences up to the
/// token budget, so a context block of ~1,200 tokens was injected for *every*
/// query - including "hi" and "what is the capital of France". That noise is
/// not merely wasted prefill (~265 s at the measured 4.58 tok/s); it is
/// emergency-priming text (triage tag colours, haemorrhage, cord delivery) fed
/// to a model that then answers "hi" in emergency register.
///
/// The corpus is English, so a query's absolute cosine depends strongly on the
/// query's script. Measured over the 32-case suite (top cosine per case):
///
///   Latin  : non-medical max 0.643 ("hi")   medical min 0.648 ("I fell")
///   Arabic : non-medical max 0.590          medical min 0.463
///
/// The cross-lingual penalty (Arabic query vs English index) is *larger than
/// the gap between relevant and irrelevant*, so no single threshold works: at
/// 0.645 Arabic loses 11 of 13 cases, 4 of them genuinely medical (stroke,
/// antibiotic dosing, burn, seizure recovery). Latin is therefore filtered and
/// Arabic is left unfiltered until cross-lingual retrieval is fixed properly.
///
/// 0.645 sits in the measured safe window [0.64, 0.648]: it silences every
/// non-medical Latin case (highest is "hi" at 0.6430) while silencing no
/// genuine Latin medical case - the nearest is "I fell" at 0.6483. The margin
/// is narrow by construction, because the two classes genuinely overlap; the
/// boundary was chosen to favour keeping context (a false keep costs tokens, a
/// false drop loses the reference). Re-measure with `rag_repro.py --cases`
/// before changing it.
const double kMinHitScoreLatin = 0.645;

class RagHit {
  final RagSentence sentence;
  final double score;
  final bool hasNeighbors;
  /// Sentence text merged with its same-chunk neighbors (when [hasNeighbors]).
  /// Null when no neighbors were merged; buildContext renders this so sibling
  /// content actually reaches the model context.
  final String? expandedText;
  const RagHit(this.sentence, this.score,
      {this.hasNeighbors = false, this.expandedText});

  /// The text to render into context: expanded when available.
  String get renderedText => expandedText ?? sentence.text;
}

class RagV3Context {
  final List<RagHit> hits;
  final String context;
  final List<String> sources;
  final int tokensEst;
  const RagV3Context({
    required this.hits,
    required this.context,
    required this.sources,
    required this.tokensEst,
  });
}

class RagV3 {
  final RagAssets assets;
  final int mmrTopN;
  final double mmrLambda;

  RagV3(this.assets, {this.mmrTopN = 40, this.mmrLambda = 0.5});

  /// Rank sentences by cosine to [queryVec] (normalized f32).
  List<RagHit> rank(Float32List queryVec, {int topK = 16}) {
    final v = assets.vectors;
    if (queryVec.length != v.cols) {
      throw ArgumentError(
        'query dim ${queryVec.length} != index dim ${v.cols}',
      );
    }
    final qn = _normalize(queryVec);
    final scored = List<double>.filled(v.rows, 0);
    for (var r = 0; r < v.rows; r++) {
      scored[r] = v.dotRow(qn, r);
    }
    // partial selection of top mmrTopN by score
    final idx = List<int>.generate(v.rows, (i) => i);
    idx.sort((a, b) => scored[b].compareTo(scored[a]));
    final cand = idx.take(mmrTopN).toList();

    // MMR diversity re-rank using q8 rows as the similarity space.
    // Matches eval/rag_mirror/rag_v2.py exactly: diversity = MAX cosine to
    // the already-selected set (not average) — verified by fixture parity.
    final selected = <int>[];
    final maxScore = scored[cand.first] <= 0 ? 1e-9 : scored[cand.first];
    while (cand.isNotEmpty && selected.length < topK) {
      int? best;
      var bestScore = -1e9;
      for (final i in cand.take(20)) {
        var div = 0.0;
        for (final j in selected) {
          final d = _cosQ(i, j);
          if (d > div) div = d;
        }
        final s = mmrLambda * (scored[i] / maxScore) - (1 - mmrLambda) * div;
        if (s > bestScore) {
          bestScore = s;
          best = i;
        }
      }
      selected.add(best!);
      cand.remove(best);
    }

    final hits = <RagHit>[];
    for (final i in selected) {
      final s = assets.sentences[i];
      hits.add(RagHit(s, scored[i]));
    }
    return hits;
  }

  /// Expand each hit with adjacent same-chunk sentences (multi-phase
  /// instructions: seizure aftercare, compression cycles, etc).
  List<RagHit> expandNeighbors(List<RagHit> hits, {int neighbors = 1}) {
    if (neighbors <= 0) return hits;
    final byChunkPos = <String, Map<int, RagSentence>>{};
    for (final s in assets.sentences) {
      (byChunkPos[s.chunkId] ??= {})[s.pos] = s;
    }
    final out = <RagHit>[];
    // Dedup key MUST include the chunk identity: pos alone collides across
    // chunks, which over-suppressed sibling expansion (review round 2).
    final used = <String>{};
    for (final h in hits) {
      final buf = StringBuffer(h.sentence.text);
      var added = false;
      for (var d = 1; d <= neighbors; d++) {
        for (final p in [h.sentence.pos - d, h.sentence.pos + d]) {
          final key = '${h.sentence.chunkId}#${h.sentence.pos}:$p';
          if (used.contains(key)) continue;
          final sib = byChunkPos[h.sentence.chunkId]?[p];
          if (sib != null) {
            buf.write(' ');
            buf.write(sib.text);
            used.add(key);
            added = true;
          }
        }
      }
      used.add('${h.sentence.chunkId}#${h.sentence.pos}:${h.sentence.pos}');
      out.add(RagHit(
        h.sentence,
        h.score,
        hasNeighbors: added,
        // Sibling text MUST reach the context: the whole point of expansion
        // (e.g. the seizure "recovery position" sibling). buildContext reads
        // this instead of re-reading the bare sentence.
        expandedText: buf.toString(),
      ));
    }
    return out;
  }

  /// Build the cited, token-budgeted context block.
  ///
  /// [minScore] drops any hit whose own cosine falls below it before neighbor
  /// expansion. Null means no floor. See [kMinHitScoreLatin] for why the caller
  /// - not this class - decides the value: it depends on the query's script.
  RagV3Context buildContext(Float32List queryVec,
      {int topK = 16,
      int maxTokens = 1100,
      int neighbors = 1,
      double? minScore}) {
    var ranked = rank(queryVec, topK: topK);
    if (minScore != null) {
      ranked = [
        for (final h in ranked)
          if (h.score >= minScore) h,
      ];
    }
    final expanded = expandNeighbors(ranked, neighbors: neighbors);
    final lines = <String>[];
    final sources = <String>[];
    var used = 0.0;
    for (var i = 0; i < expanded.length; i++) {
      final t = expanded[i].renderedText;
      final cost = t.length / 3.7 + 12;
      if (used + cost > maxTokens) continue;
      lines.add('- $t [${lines.length + 1}]');
      used += cost;
      final src = expanded[i].sentence.source;
      if (!sources.contains(src)) sources.add(src);
    }
    return RagV3Context(
      hits: expanded,
      context: lines.isEmpty ? 'NO_RELEVANT_CONTEXT' : lines.join('\n'),
      sources: sources,
      tokensEst: used.toInt(),
    );
  }

  double _cosQ(int a, int b) {
    final v = assets.vectors;
    final offA = a * v.cols;
    final offB = b * v.cols;
    var dot = 0.0;
    for (var i = 0; i < v.cols; i++) {
      dot += v.data[offA + i] * v.data[offB + i];
    }
    return dot * v.scales[a] * v.scales[b]; // rows unit-norm pre-quant
  }

  static Float32List _normalize(Float32List v) {
    var n = 0.0;
    for (final x in v) {
      n += x * x;
    }
    n = n <= 0 ? 1.0 : _sqrt(n);
    final out = Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      out[i] = v[i] / n;
    }
    return out;
  }

  static double _sqrt(double x) {
    // Newton-Raphson; avoids dart:math import in hot path tests on web.
    var r = x;
    for (var i = 0; i < 12; i++) {
      r = 0.5 * (r + x / r);
    }
    return r;
  }
}
