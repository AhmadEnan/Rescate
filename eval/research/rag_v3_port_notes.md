// apps/rescate_app/lib/features/ai_chat/state/model_store.dart — n/a
//
// design_notes/rag_v3_port.md (kept in eval/ for the night build; NOT app code)
//
// Port plan for rag_v2 -> Dart (rag_v3) inside packages/ai_inference:
//
// 1. Asset: replace assets/chunks.json usage with:
//    - assets/rag_sentences.json   (7019 sentence units: id, chunk_id, source, text)
//    - assets/rag_vectors.bin      (7019 x 1024 float32 = 27.5 MB; or int8
//                                   quantized per-dim -> ~7 MB with <0.5% recall
//                                   loss measured on the suite)
//    Generated offline by the python pipeline (eval/rag_mirror/).
//
// 2. Embedder: llamadart already embeds GGUF models? NO — current llamadart
//    version is generate-only. Two options, decision needed:
//    a) bundle a second tiny GGUF (Qwen3-Embedding-0.6B-Q8, 610MB too big for
//       the app; use Q4/Q5 ~350-400MB — still heavy but acceptable offline) and
//       run it in-process; OR
//    b) store the embedding table AND a small hand-rolled ONNX/int8 embedder
//       via tflite (multilingual-e5-small int8 ~30MB). Better size, more glue.
//    Recommendation: (b) if tflite already in deps, else (a).
//
// 3. Runtime flow per turn (replaces LegacyRag.search):
//    - embed query (10-50ms int8 on 2 big cores)
//    - cosine over Float32List matrix (vectorized, <10ms at 7k rows in Dart
//      with SIMD-friendly loop; measured ~35ms naive)
//    - BM25 over precomputed inverted index (~15ms)
//    - RRF fuse + MMR (lambda=0.5) (<2ms)
//    - budgeted context assembly (~1ms)
//    Total <100ms on MT6893 target — fits the existing rag.search budget.
//
// 4. Prompt: same MEDICAL REFERENCE block, but now whole sentences with [n]
//    citations; system prompt gains: "Cite [n] for every instruction you take
//    from the reference. If the reference does not cover the question, say so
//    and give the safest universal first-aid action + emergency call guidance."
//
// 5. Eval contract: any change to rag_v3 Dart lands only after the same 48-case
//    suite passes >= rag_v2 numbers via a Dart harness (flutter test) reading
//    the same assets.
