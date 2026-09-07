# Edge LLMs for Rescate (Sep 2025 – Sep 2026)

Research for issue #14: candidate on-device models for bilingual (EN/AR) grounded
first-aid RAG on phone CPU. Current baseline: **Gemma 4 E2B-it Q4_K_M**
(Apache 2.0, ~2B effective params, 256K context, 140+ languages).
Compiled 2026-09-07 by the Rescate eval harness effort; every claim source-linked.

## Shortlist (ranked)

### 1. Qwen3.5-2B (Apache 2.0) — benchmark first
- **Repo:** `unsloth/Qwen3.5-2B-GGUF` (UD-Q4_K_XL / Q4_K_M ~1.5 GB file size per CanIRun quant table)
- **Why:** Qwen family leads the 2026 Arabic procurement matrix (ALUE strong 80%+
  on most subtasks; ArabicMMLU high-60s/mid-70s on larger variants; best dialect
  coverage of the three multilingual flagships) — Hosn Arabic eval, May 2026.
  32K context, hybrid Gated DeltaNet architecture, 201 training languages,
  llama.cpp support confirmed via Unsloth GGUF.
- **Fit:** strongest documented Arabic quality at this size + permissive license.
  Risk: hybrid linear-attention arch needs a recent llama.cpp — pin the build.

### 2. SILMA Kashif 2B Instruct v1.0 (Gemma license) — benchmark first
- **Repo:** `silma-ai/SILMA-Kashif-2B-Instruct-v1.0` (GGUF conversions community-made)
- **Why:** purpose-built **Arabic RAG** model (EN+AR contextual QA). Explicitly
  trained for: negative rejection ("answer cannot be found in the given context"
  — exactly our out-of-scope safety behavior), multi-hop, tabular/numerical
  grounding, medical/legal domains. Top open RAG model 3–9B on SILMA RAGQA.
  12k context. Gemma-2 architecture → works on existing llama.cpp.
- **Fit:** the specialization matches Rescate's core loop (context-grounded
  bilingual QA with refusal). Caveats: RAG-only model (general chat will suffer),
  Gemma license terms, and its Arabic MSA benchmarks skew finance/tabular — must
  validate on first-aid content.

### 3. Gemma 4 E4B-it (Apache 2.0) — upgrade path
- **Repo:** `unsloth/gemma-4-E4B-it-GGUF`
- **Why:** same family as the current baseline, ~2× effective compute (E4B),
  keeps the prompt template, tool-calling story, and llamadart integration
  identical. If E2B quality is the ceiling and RAM allows (~4-5 GB 4-bit),
  this is the lowest-risk quality bump.
- **Fit:** safe incremental step; measure whether E4B fits phone RAM budget.

### 4. Jais-family-2.7b-chat (Jais Family Model License — restricted)
- **Repo:** `inceptionai/jais-family-2p7b-chat`; GGUF: `RichardErkhov/inceptionai_-_jais-adapted-7b-chat-gguf` (7B variant, Q4_K_M ~3.97 GB)
- **Why:** Arabic-first family (EN/AR bilingual pretraining), 512K vocab
  optimized for Arabic. Evidence of strong Arabic in OALL-style benchmarks.
- **Fit:** license is NOT clearly redistributable in an app (custom terms) and
  family GGUFs are third-party. Explore for quality ceiling only; flag as
  license-blocked for shipping unless terms are cleared with Inception.

### 5. IBM Granite 4.0 Micro (~3B, Apache 2.0)
- **Repo:** `ibm-granite/granite-4.0-micro`
- **Why:** Apache 2.0, hybrid Mamba-2/transformer, conservative/RAG-oriented
  training focus, IBM's enterprise vetting. Arabic evidence thin.
- **Fit:** dark-horse candidate; include in round 2 if round-1 disappoints.

### 6. Gemma 4 E2B-it (Apache 2.0) — the incumbent baseline
- **Repo:** `unsloth/gemma-4-E2B-it-GGUF` — what the app ships today.
- **Fit:** every candidate must beat this on the eval suites at acceptable
  tok/s. Documented weakness: ArabicMMLU low-to-mid 60s (behind Qwen), dialect
  ID weak — but fluent, usable Arabic in practice.

### 7. Fanar 1-9B (QCRI) — Arabic-first, license to verify
- **Repo:** `QCRI/Fanar-1-9B` (~1.9B params). Qatar's Arabic-focused family.
- **Fit:** promising size class; license (CC-style QCRI terms) and GGUF
  availability need verification before investing benchmark time.

### 8. SmolLM3-3B (Apache 2.0)
- **Repo:** `ggml-org/SmolLM3-3B-GGUF`
- **Fit:** strong small-model reasoning, but no particular Arabic strength —
  include only as a control point.

## Benchmark first (in order)

1. **Qwen3.5-2B** — best-documented Arabic at the right size, Apache 2.0,
   GGUF ready. Highest expected value.
2. **SILMA Kashif 2B** — RAG-specialized with trained refusal behavior; tests
   whether task specialization beats general capability at equal size.
3. **Gemma 4 E4B** — incumbent-family scale-up; isolates "more compute" from
   "different model," and reuses everything we already have.

## On-device / llama.cpp gotchas

- **Qwen3.5** hybrid Gated DeltaNet: needs recent llama.cpp; verify llamadart
  bundles a compatible llama.cpp before committing. Older runtimes silently
  produce garbage or fail to load.
- **Gemma 3n/4 E-models** hybrid (per-layer embedding offload): fast-growing
  support area; the app's current Vulkan/CPU ladder and `_compactSnippet`
  prompt sizing were tuned on E2B — re-tune for E4B (RAM doubles).
- **Jais** tokenizer (512K Arabic-heavy vocab) → larger embedding tables;
  expect bigger GGUF than parameter count suggests.
- **SILMA Kashif**: RAG-only — do not benchmark on open-ended chat cases;
  its refusal behavior ("cannot be found in context") should score
  artificially well on `oos` cases unless prompts match its training format.
- CPU-only ladder (Dimensity 1200 lesson): prefill batch sizes 256/128 remain
  the reference; any candidate slower than ~2 tok/s decode on 2 big cores is
  out regardless of quality.

## Sources

- Unsloth Gemma 4 guide + E2B/E4B GGUFs: https://docs.unsloth.ai/models/gemma-4 , https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF , https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF
- Gemma 4 license (Apache 2.0): https://ai.google.dev/gemma/docs/gemma_4_license
- Hosn Arabic eval (ALUE/ArabicMMLU/AraBench across Gemma 4 / Llama 4 / Qwen): https://hosn.om/blog/gemma-4-llama-4-qwen-3-6-arabic-eval.html
- Qwen3.5 small-series deployment (0.8B-9B, GGUF, llama.cpp): https://besthub.dev/articles/how-to-deploy-and-fine-tune-qwen3-5-small-models-0-8b-9b-locally-476e9d1e67b8 ; https://huggingface.co/unsloth/Qwen3.5-2B-GGUF ; Apache 2.0 license: https://huggingface.co/Qwen/Qwen3.5-35B-A3B/blob/main/LICENSE
- SILMA Kashif 2B (Arabic RAG, refusal training, RAGQA benchmark): https://huggingface.co/silma-ai/SILMA-Kashif-2B-Instruct-v1.0
- Arabic LLM landscape incl. Fanar/Jais/ALLaM licensing: https://huggingface.co/blog/silma-ai/arabic-llm-models-list
- Jais family cards + GGUF availability: https://huggingface.co/inceptionai/jais-family-2p7b-chat ; https://huggingface.co/RichardErkhov/inceptionai_-_jais-adapted-7b-chat-gguf
- Fanar: https://huggingface.co/QCRI/Fanar-1-9B
- Granite 4.0 Micro (Apache 2.0): https://huggingface.co/ibm-granite/granite-4.0-micro ; https://github.com/ibm-granite/granite-4.0-language-models/blob/main/LICENSE
- Small-LM Arabic processing survey (arXiv 2606.21460): https://arxiv.org/abs/2606.21460
- Falcon-H1 (hybrid arch, permissive-but-structured TII license): https://huggingface.co/tiiuae/Falcon-H1-1.5B-Instruct
