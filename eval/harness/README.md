# Rescate Eval Harness (issue #14 exploration)

Everything here is exploration tooling, **not shipped app code**. It mirrors the
app's AI workflow outside Flutter so models, retrieval, and prompts can be
measured and iterated on quickly.

## Layout

```
eval/
├── rag_mirror/legacy_rag.py     # 1:1 Python port of packages/ai_inference LegacyRag
│   └── rag_tables.json          # arEnMap/actionTerms/stopwords extracted FROM the Dart source
├── datasets/
│   ├── bilingual_qa_v1.json     # EN/AR emergency QA + out-of-scope safety probes
│   └── retrieval_suite_v1.json  # 30-case retrieval suite (corpus-validated)
├── harness/
│   ├── llm_harness.py           # backends: llama-cpp-python or llama-server (OpenAI-compat)
│   ├── run_eval.py              # batch eval: RAG + model over a dataset
│   ├── discord_bridge.py        # Discord<->model+RAG mirror (queue-based)
│   └── models.json              # candidate model registry
├── grading/retrieval_metrics.py # hit@k / MRR / snippet metrics + corpus validation
├── results/                     # JSON reports (gitignored outputs live here)
├── queue/                       # Discord bridge queue (inbox/ outbox/)
└── research/                    # model research reports
```

## Quick start

```bash
# 1. Retrieval baseline (no model needed — runs in seconds)
python3 eval/grading/retrieval_metrics.py

# 2. One question through the full pipeline (needs a model — see below)
python3 eval/harness/discord_bridge.py --oneshot "how do I treat a second degree burn?"

# 3. Full eval run
python3 eval/harness/run_eval.py --model gemma-4-e2b-q4km
```

## Getting a model

Either download a GGUF (see `models.json` for candidates):

```bash
huggingface-cli download unsloth/gemma-4-E2B-it-GGUF gemma-4-E2B-it-Q4_K_M.gguf --local-dir eval/models/
```

or point at an already-running llama.cpp server:

```bash
RESCATE_EVAL_SERVER_URL=http://127.0.0.1:8080 python3 eval/harness/run_eval.py --model gemma-4-e2b-q4km
```

## Discord mirror

The Hermes Discord bot owns the Discord connection. It writes user questions
into `eval/queue/inbox/<id>.json` (`{"id": "...", "text": "..."}`) and reads
replies from `eval/queue/outbox/<id>.json` (`{"reply": "..."}`). Start the
bridge:

```bash
python3 eval/harness/discord_bridge.py --model gemma-4-e2b-q4km --poll
```

Replies cite the retrieved chunk sources + scores, so retrieval quality is
visible directly in conversation.

## Grading layers

1. **Automatic** (in `run_eval.py`): `must_contain_any` / `must_not_contain_any`
   keyword contracts per case — cheap, deterministic regression protection.
2. **Retrieval metrics** (`retrieval_metrics.py`): hit@k, MRR,
   snippet-contains-answer, split by language.
3. **Rubric grading** (`grading/rubric.md`): clinical-quality rubric for manual
   or LLM-as-judge scoring of transcripts.

## Baseline (2026-09-06, mirror retriever, current corpus)

- Retrieval hit@5 = 0.60 (EN 0.60 / AR 0.60), MRR 0.38
- **Snippet contains the decisive answer only 13% of the time** — the dominant
  quality problem: the right document is retrieved but the 180-char snippet
  window misses the actionable sentence.
- See `results/retrieval_baseline.json` for per-case detail.
