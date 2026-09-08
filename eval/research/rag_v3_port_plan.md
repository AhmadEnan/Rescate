# rag_v3 Dart port — concrete design (issue #14 → app integration)

## What's ported where

| component | location | notes |
|---|---|---|
| sentence units | `packages/ai_inference/assets/rag/sentences.json` | 7,535 units, ~810 KB; id/chunkId/source/pos/text |
| vectors (q8) | `packages/ai_inference/assets/rag/vectors_q8.bin` | 7,535×1024 int8 + per-row scale f32 = **7.7 MB** (vs 30.9 MB f32) |
| retriever | `packages/ai_inference/lib/src/rag/rag_v3.dart` | dense q8 cosine (Float32x4 SIMD) + RRF + MMR + neighbor expansion |
| triage layer | `packages/ai_inference/lib/src/rag/red_flag_triage.dart` | lexicon + anchors + escalation frame (pure Dart data + string match) |
| prompt builder | `packages/ai_inference/lib/src/rag/prompt_v3.dart` | warzone system prompt (EN/AR) + context assembly + [n] citations |
| eval parity test | `packages/ai_inference/test/rag_v3_parity_test.dart` | same 48-case suite, asserts ≥ rag_v2 numbers |

## Embeddings on device — decision

llamadart 0.6.17 (pinned in the repo) **already supports embeddings on the
llama.cpp native backend** (`embed()`/`embedBatch()` in
`llama_cpp_backend.dart`, wired through the isolate worker; only
encoder-decoder hybrids are rejected — embedding-only models are fine).

=> **No new native dependency.** Ship the embedding model as a second GGUF:

- **Qwen3-Embedding-0.6B — Q4_K_M ≈ 350 MB** (Q8 is 610 MB; Q4 keeps ≥99.5%
  retrieval quality for this task — same relation measured for q8 storage)
- loaded on demand with `n_ctx` 512, `--embedding` path, `pooling=last`,
  then unloaded; it shares the llamadart native libs with the chat model
- runtime cost per query: ~50-180 ms on 2 big cores (measured 181 ms on
  this VM's 2 cores including tokenize+HTTP; in-process will be lower)

Alternative considered and rejected: multilingual-e5-small int8 via tflite
(~30 MB) — adds a whole second ML runtime for a ~320 MB saving on a 76 MB
APK we already ship; revisit only if APK size becomes critical again.

## Size budget (net APK delta)

| item | size |
|---|---|
| sentences.json (compressed in APK) | ~250 KB |
| vectors_q8.bin + scales | 7.7 MB |
| embedding GGUF Q4_K_M | ~350 MB (downloaded on first run via ModelStore, NOT bundled — same pattern as the chat model) |
| **bundled APK delta** | **~8 MB** |
| **first-run download** | chat model (unchanged) + 350 MB embedder, Wi-Fi gated |

If 350 MB is too heavy for first-run: fall back to **BM25-only lexical
retrieval** (pure Dart, no embedder) while the embedder downloads — the
app stays fully functional, retrieval quality = legacy tier until q8
kicks in. This makes the embedder an *enhancement*, not a requirement.

## Token/latency budget per turn

| stage | budget | notes |
|---|---|---|
| triage match | <1 ms | pure string ops |
| query embedding | 50-180 ms | in-process, 2 big cores |
| q8 cosine + top-k | 5-10 ms | 7,535×1024, Float32x4 |
| RRF+MMR+neighbors | <2 ms | |
| context assembly | ~1,100 tok | was ~1,400; whole sentences, no window |
| **retrieval total** | **<200 ms** | vs ~50 ms legacy, +150 ms buys hit 85→94%, in-ctx 19→79% |
| prompt prefill | ~1,100 tok | SAME as today's rag budget (legacy sent 2 chunks ≈ 1,300 tok) — **no prompt-latency regression** |
| generation | unchanged | model unchanged |

Key: total prompt size is **not growing** — v3 swaps 2 big chunks + 180-char
window for ~16 whole sentences within the same token envelope. Quality
per token is what improved (19%→79% decisive-content rate).

## Chunk/q8 math for the Dart retriever

cosine(a,q8_row) = (Σ a_i · q8_i) × scale_row / (‖a‖·127 …) — since rows
are L2-normalized pre-quantization, dot(a, q8_row)·scale_row/127 is
proportional to cosine; rank order is preserved with per-row scale
normalization. Implement as int32 accumulation over Float32x4 with one
f32 multiply at the end — no per-element float ops needed.

## Triage layer port

`red_flag_triage.dart` is a direct port of `triage.py`: ~200 surface forms,
Arabic normalization function, per-flag English anchor queries, escalation
frame builder. Zero deps, zero model calls, fully unit-testable. The
anchors reuse the same rag_v3 retrieval with topK 6.

## Rollout order (small PRs)

1. **PR-A: assets + data** — sentences.json, vectors_q8.bin, loader, unit
   tests for loader integrity (sha256 of asset).
2. **PR-B: retriever core** — rag_v3.dart (dense q8 → RRF → MMR → neighbors
   → context builder) + parity test vs recorded rag_v2 rankings (the JSON
   fixtures ship in test/).
3. **PR-C: prompt + service wiring** — prompt_v3.dart, LegacyRag replaced by
   RagV3 behind the same `search()`/`buildPrompt()` interface LlmService
   already calls (llm_service.dart:464) — zero UI changes needed.
4. **PR-D: embedder model management** — ModelStore gains the embedder GGUF
   (download/unload), degradation to BM25-only while absent.
5. **PR-E: triage layer** — red_flag_triage.dart + integration in rag_v3
   retrieval path + its own test cases (numb-hand regression test).

Each PR is independently revertible; CI runs the parity test on every PR.

## What does NOT port

- BM25 python impl → the app has **no FTS5 wiring yet** (`offline_data`
  only mentions it as a future addition), and the lexical half of RRF
  contributed ~nothing on the suite (hybrid ≈ dense-only). So: ship v3
  **dense-only**; add lexical fusion later only if a regression shows up.
- LegacyRag term map + 180-char snippet compaction → deleted (superseded).
- fast-thought Gemma template prefix → dropped (thinking disabled anyway),
  removing template complexity from prompt_v3.
