// Review-fix regression tests (PR #29 review follow-up):
//  - P0 #1: service-level anchor-vector wiring (registration reaches the
//    triage instance; force-injection works without a live embedder)
//  - P0 #2: Arabic triage precedence (normalized-changing forms like
//    ألم→الم / إصابة→اصابه must match)
//  - #3: neighbor expansion actually renders sibling text into context
//  - #4: v3 prompt preserves toolDeclarations / enableThinking
//  - #5: embedder filename contract matches the app registry
//
// Uses synthetic RagAssets (4 sentences, one chunk, 8-dim vectors) so every
// force-injection path is deterministic — no live embedder required.
import 'dart:typed_data';

import 'package:ai_inference/src/rag/prompt_v3.dart';
import 'package:ai_inference/src/rag/rag_assets.dart';
import 'package:ai_inference/src/rag/rag_service.dart';
import 'package:ai_inference/src/rag/rag_v3.dart';
import 'package:ai_inference/src/rag/red_flag_triage.dart';
import 'package:ai_inference/src/rag/triage_context.dart';
import 'package:ai_inference/src/rag/embedder_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _dim = 8;

RagAssets _syntheticAssets() {
  final sentences = <RagSentence>[
    const RagSentence(
        id: 'a0',
        chunkId: 'chunk-a',
        source: 'src_stroke',
        pos: 0,
        text: 'STROKE GUIDANCE: sudden weakness on one side is an emergency'),
    const RagSentence(
        id: 'a1',
        chunkId: 'chunk-a',
        source: 'src_stroke',
        pos: 1,
        text: 'Place the person in the recovery position on their side'),
    const RagSentence(
        id: 'b0',
        chunkId: 'chunk-b',
        source: 'src_bleed',
        pos: 0,
        text: 'BLEEDING GUIDANCE: apply firm direct pressure to the wound'),
    RagSentence(
        id: 'c0',
        chunkId: 'chunk-c',
        source: 'src_misc',
        pos: 0,
        text: 'General advice: '
            'keep the person warm and monitor breathing. ' * 60),
  ];
  // 16 dummy rows AFTER the real ones: base retrieval (topK=16) fills on
  // query-matched + dummy rows first, so the stroke rows fall OUTSIDE base —
  // reproducing production (7,535 rows) where base doesn't cover the anchor
  // content. Force-injection is what must rescue it.
  // Dummies FIRST: MMR tie-breaks by index, so base (topK=16) fills with
  // dummy rows + misc, leaving stroke rows OUTSIDE base — the production
  // scenario (7,535 rows never fully fit base) where force-injection is
  // what rescues the emergency guidance.
  final rows = [
    for (var i = 0; i < 16; i++)
      RagSentence(
          id: 'd$i',
          chunkId: 'chunk-d$i',
          source: 'src_dummy$i',
          pos: 0,
          text: 'dummy filler row $i ${'x' * 240}'),
    ...sentences,
  ];
  final n = rows.length;
  final data = Int8List(n * _dim);
  final scales = Float32List(n);
  // rows 0..15: dummies hot on dim 7; row 16: misc dim 3; rows 17,18:
  // stroke dim 0; row 19: bleed dim 2.
  for (var i = 0; i < 16; i++) {
    data[i * _dim + 7] = 100;
    scales[i] = 0.01;
  }
  data[16 * _dim + 3] = 100;
  scales[16] = 0.01;
  data[17 * _dim + 0] = 100;
  scales[17] = 0.01;
  data[18 * _dim + 0] = 100;
  scales[18] = 0.01;
  data[19 * _dim + 2] = 100;
  scales[19] = 0.01;
  return RagAssets(
    sentences: rows,
    vectors: RagVectors(rows: n, cols: _dim, data: data, scales: scales),
  );
}

/// Unit vector along [hot]: dequantizes to exactly dimension [hot]'s unit,
/// matching synthetic row [hot] with cosine 1.0.
Float32List _vec(int hot) {
  final v = Float32List(_dim);
  v[hot % _dim] = 1.0;
  return v;
}

void main() {
  group('P0 #1: anchor-vector service wiring', () {
    test('service registration reaches the triage instance', () {
      final rag = RagV3WithTriage(RagV3(_syntheticAssets()));
      final svc = RagService.forTest(rag);

      // Before registration: triage fires but injection degrades (no crash).
      final before = svc.buildContextForTest(
          _vec(0), 'someone collapsed and not waking up');
      expect(before.hasRedFlag, isTrue);
      expect(before.injectedSources, isEmpty,
          reason: 'unregistered anchor must degrade, not throw');

      // Register the unconscious anchor; its anchor vector points at the
      // stroke rows (dim 0). The QUERY vector points at src_misc (dim 3) —
      // base retrieval misses the emergency guidance, and force-injection
      // is what rescues it. (If queryVec pointed at the stroke rows too,
      // base would already contain them and dedup would legitimately
      // leave injectedSources empty.)
      svc.registerAnchorVector('unconscious', _vec(0).toList());

      final after = svc.buildContextForTest(
          _vec(3), 'someone collapsed and not waking up');
      expect(after.hasRedFlag, isTrue);
      expect(after.injectedSources, isNotEmpty,
          reason: 'registered anchor must run force-injection (it retrieves '
              'the flag guidance; dedup against base is expected behavior)');
      expect(after.escalationFrame, contains('unresponsive person'));
      expect(after.contextWithFrame, contains('recovery position'),
          reason: 'injected stroke guidance must be in the final context');
    });

    test('partial registration skips only the missing flag', () {
      final rag = RagV3WithTriage(RagV3(_syntheticAssets()));
      // Register every flag EXCEPT uncontrolled_bleeding; its anchor then
      // degrades gracefully while the frame still fires.
      for (final f in kRedFlags) {
        if (f.id == 'uncontrolled_bleeding') continue;
        rag.registerAnchorVec(f.id, _vec(0));
      }
      final ctx = rag.buildContext(
        _vec(2), // bleed row direction for base retrieval
        "cut that won't stop bleeding",
      );
      expect(ctx.hasRedFlag, isTrue);
      expect(ctx.escalationFrame, isNotEmpty,
          reason: 'escalation frame must fire even without the anchor');
    });
  });

  group('P0 #2: Arabic triage precedence', () {
    test('normalized-changing forms match after normalization', () {
      // These forms CHANGE under normalizeArabic (alef variants, taa
      // marbuta): ألم→الم, إصابة→اصابه. The old ternary made them
      // unmatchable when spelled with hamza carriers. Lexicon forms are
      // chest/head-specific, so the queries use the full phrases.
      expect(
        triageQuery('عندي ألم في الصدر و ضيق').map((h) => h.flag.id),
        contains('chest_pain'),
        reason: 'ألم في الصدر (hamza spelling) must match chest_pain',
      );
      expect(
        triageQuery('عنده الم في الصدر و ضيق').map((h) => h.flag.id),
        contains('chest_pain'),
        reason: 'bare-alef spelling must match too',
      );
      expect(
        triageQuery('عنده إصابة في الرأس').map((h) => h.flag.id),
        contains('head_trauma'),
        reason: 'إصابة في الرأس must match head_trauma',
      );
    });

    test('Arabic stroke red flags still fire (regression guard)', () {
      expect(
        triageQuery('صحيت لقيت ايدي منملة').map((h) => h.flag.id),
        contains('stroke'),
      );
      expect(
        triageQuery('رجلهم مش بيتحرك و فيه شلل').map((h) => h.flag.id),
        contains('stroke'),
      );
    });

    test('benign queries stay clean (false-positive guard)', () {
      expect(triageQuery('ازاي اعمل جبس لكسر بسيط في الصباع'), isEmpty);
      expect(triageQuery('ايه حاجات اساسية للاسعافات الاولية'), isEmpty);
    });
  });

  group('#3: neighbor expansion reaches context', () {
    test('buildContext renders sibling text, not the bare sentence', () {
      final rag = RagV3(_syntheticAssets());
      // Row 0 and row 1 are the same chunk (chunk-a): a hit on row 0 with
      // neighbors=1 MUST pull row 1's sentence into the rendered context.
      final ctx = rag.buildContext(_vec(0), topK: 1, neighbors: 1);
      expect(ctx.context, contains('recovery position'),
          reason: 'sibling sentence must reach the context');
      final hit = ctx.hits.first;
      expect(hit.hasNeighbors, isTrue);
      expect(hit.expandedText, isNotNull);
      expect(hit.expandedText, contains('recovery position'));
    });
  });

  group('#4: v3 prompt preserves tool declarations', () {
    test('toolDeclarations are rendered into the v3 system turn', () {
      const tools = '{"name":"call_emergency","description":"Dial 123"}';
      final p = buildGemmaPromptV3(
        context: '- pressure the wound [1]',
        question: 'someone is bleeding',
        arabic: false,
        toolDeclarations: tools,
      );
      expect(p, contains(tools));
    });

    test('enableThinking=true omits the prefilled thought', () {
      final thinking = buildGemmaPromptV3(
        context: '- x [1]',
        question: 'q',
        arabic: false,
        enableThinking: true,
      );
      expect(thinking, isNot(contains('<|channel>thought')));
      final fast = buildGemmaPromptV3(
        context: '- x [1]',
        question: 'q',
        arabic: false,
        enableThinking: false,
      );
      expect(fast, contains('<|channel>thought'));
    });

    test('toolDeclarations present on the RagService v3 path', () {
      final rag = RagV3WithTriage(RagV3(_syntheticAssets()));
      final svc = RagService.forTest(rag)
        ..registerAnchorVector('unconscious', _vec(0).toList());
      final result = svc.buildPromptForTest(
        question: 'someone collapsed',
        queryVec: _vec(0),
        toolDeclarations: '{"name":"call_emergency"}',
      );
      expect(result.prompt, contains('"name":"call_emergency"'));
    });
  });

  group('round 2: fallback path runs triage (no embedder needed)', () {
    test('fallback stroke query gets escalation frame + triaged=true', () {
      final rag = RagV3WithTriage(RagV3(_syntheticAssets()));
      final svc = RagService.forTest(rag);
      // queryVec = null forces the LegacyRag fallback path.
      final result = svc.buildPromptForTest(
        question: 'someone collapsed and not waking up',
        queryVec: null,
      );
      expect(result.triaged, isTrue,
          reason: 'fallback must run string triage');
      expect(result.prompt, contains('TRIAGE ALERT'),
          reason: 'escalation frame must be injected in the fallback path');
      expect(result.prompt, contains('unresponsive person'));
    });

    test('fallback benign query stays clean (no frame, triaged=false)', () {
      final rag = RagV3WithTriage(RagV3(_syntheticAssets()));
      final svc = RagService.forTest(rag);
      final result = svc.buildPromptForTest(
        question: 'what should a basic first aid kit contain',
        queryVec: null,
      );
      expect(result.triaged, isFalse);
      expect(result.prompt, isNot(contains('TRIAGE ALERT')));
    });
  });

  group('round 2: neighbor dedup key is chunk-aware', () {
    test('same pos in different chunks both expand their own siblings', () {
      // Two chunks, each with pos 0/1. Old key (pos*100000+p) collided:
      // the second chunk's hit suppressed its sibling expansion.
      final sentences = <RagSentence>[
        const RagSentence(
            id: 'x0', chunkId: 'cx', source: 'sx', pos: 0, text: 'alpha text'),
        const RagSentence(
            id: 'x1', chunkId: 'cx', source: 'sx', pos: 1, text: 'beta sibling'),
        const RagSentence(
            id: 'y0', chunkId: 'cy', source: 'sy', pos: 0, text: 'gamma text'),
        const RagSentence(
            id: 'y1', chunkId: 'cy', source: 'sy', pos: 1, text: 'delta sibling'),
      ];
      final data = Int8List(4 * _dim);
      final scales = Float32List(4);
      for (var i = 0; i < 4; i++) {
        data[i * _dim + i] = 100;
        scales[i] = 0.01;
      }
      final assets = RagAssets(
        sentences: sentences,
        vectors: RagVectors(rows: 4, cols: _dim, data: data, scales: scales),
      );
      final rag = RagV3(assets);
      final hits = [
        RagHit(sentences[0], 1.0), // cx pos0
        RagHit(sentences[2], 0.9), // cy pos0 — same pos index, other chunk
      ];
      final expanded = rag.expandNeighbors(hits, neighbors: 1);
      expect(expanded[0].expandedText, contains('beta sibling'));
      expect(expanded[1].expandedText, contains('delta sibling'),
          reason: 'cross-chunk same-pos hits must NOT suppress each other');
    });
  });

  group('#5: embedder filename contract', () {
    test('service constant matches the app registry download name', () {
      // The registry (apps/rescate_app/.../known_models.dart) downloads the
      // embedder as qwen3-embedding-0.6b-q5km.gguf; EmbedderService must
      // look for exactly that name or the downloaded model never activates.
      expect(EmbedderService.kEmbedderFile, 'qwen3-embedding-0.6b-q5km.gguf');
    });
  });
}
