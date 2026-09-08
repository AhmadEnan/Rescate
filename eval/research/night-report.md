# Rescate night-build report: RAG v2 → warzone corpus → model choice

Night run for issue #14 ("best working multi-language edge-device agent").
Everything below is measured, on this VM, with transcripts saved in
`eval/results/`. All work is on local branch `feature/eval-harness-2` —
**nothing pushed, no PRs** (per instruction).

## The pipeline that exists by morning

```
query (EN or AR)
  └─ rag_v2: sentence-level retrieval over 7,535 units (317 chunks)
       · Qwen3-Embedding-0.6B Q8 (llama.cpp --embedding, 1024-dim)
       · dense cosine + BM25 → RRF → MMR (λ=0.5)
       · neighbor-sentence expansion (±1, same chunk)
       · whole-sentence cited context, ~1,100-token budget
  └─ warzone system prompt (EN/AR mirror):
       safety-first → immediate actions → prolonged care → escalation,
       no-ambulance assumption, OOS medication guard, tourniquet scope
  └─ model: Gemma-4-E2B Q4_K_M (Gemma-4 native template)
```

## What was added this session

1. **Warzone corpus** from a verifiable public source: **IFRC International
   First Aid, Resuscitation and Education Guidelines 2025** (594-page PDF,
   ifrc.org). 5 chunks / 67k chars: conflict-settings safety & prolonged
   care, severe bleeding (tourniquet/packing/pressure), open chest wounds
   (blast/gunshot), burns/inhalation, fractures/crush.
2. **Prompts rewritten** for conflict reality (EN+AR): no "call 911" as
   default ending; safety-of-responder first; prolonged-care monitoring;
   explicit OOS medication refusal; direct-pressure vs embedded-object rule.
3. **rag_v2 neighbor expansion** — fixed the "phase-2 instructions missing"
   failure class (seizure aftercare now in context: probe False→True).
4. **Grader v4** — hard checks are now negation-scoped and citation-aware
   ("do NOT apply ice" is correct advice, not a violation; quoting the
   reference inside a refusal is not dosing advice). This removed 3 false
   hard-fails that were hiding real behavior.

## Results

### Retrieval (48-case suite, EN/AR balanced)
| system | hit@k | answer-in-context |
|---|---|---|
| legacy (chunks+termmap+180ch) | 85% | 19% |
| rag_v2 (sentences+embed+RRF) | 92% | 79% |
| rag_v2 + warzone corpus + neighbors | 94% (45/48) | 79% (38/48) |

### End-to-end (15-case bilingual QA, grader v4)
| run | pass | real hard-fails |
|---|---|---|
| E2B-Q4, rag_v2 (pre-warzone) | 47% | 0 |
| E2B-Q4, warzone corpus+prompt | 47% | 0 |
| E2B-Q4, + neighbors | 47% | 0 |
| E2B-Q4, + OOS guard (**final**) | **47%** | **0** |
| Qwen3.5-Q3, final pipeline | 33% | **2** (OOS leak) |

### Model verdict (kept from the quant ladder, re-confirmed)
- **Gemma-4-E2B Q4_K_M = the pick.** Only model that never violates safety
  under any prompt; respects the OOS guard; balanced EN/AR.
- Qwen3.5-Q3: fastest (4.4 tok/s) and great AR retrieval synergy, but it
  follows the reference over the system prompt — answered the OOS
  antibiotic question with a drug name. Under reference pressure it is
  unsafe. Would need corpus-side dosage scrubbing before it's eligible.
- SILMA Kashif: safest answers but weakest construction; quant-invariant.
- MiniCPM5-2B: weakest Arabic; MiniCPM-2B-dpo conversion crashes llama.cpp.

## Honest interpretation of the 47%

The pass rate is pinned by the keyword contracts, not by answer quality:
transcripts show answers became longer, structured, and warzone-aware while
the score stayed flat. The three real quality wins this session are
invisible to raw keyword scoring:
- 0 real hard-fails across all E2B configs (was 1-2 earlier),
- OOS refusal now works in both languages (was a dose leak),
- seizure/bleeding answers carry the full correct protocol.
The graded ceiling is a dataset-v3 job: rewrite contracts to be
corpus-validated (only require what the corpus actually provides near that
topic) + add rubric-based LLM judging. That is the next work item.

## What I'd do next (in order)

1. **Dataset v3**: regenerate contracts from corpus-validated markers +
   add ~15 warzone-specific cases (tourniquet timing, chest wound
   positioning, prolonged-care monitoring). This makes the score a true
   quality measure.
2. **Qwen eligibility path**: strip/flag prescription-dosage fragments in
   the indexed sentences (corpus hygiene, not prompt) — then re-test. If
   it respects OOS then, its speed/AR profile wins over E2B.
3. **LLM-judge rubric** (`grading/rubric.md` is ready) on the ~6 saved
   transcripts per model for a clinical-quality view beyond keywords.
4. **Port plan** for the app (`research/rag_v3_port_notes.md`): assets
   (sentences.json + int8 vectors ≈ 7MB), embedder choice, <100ms runtime
   budget on the target phone.

## Repro

```
eval/.venv/bin/python rag_system/merge_warzone_corpus.py       # corpus
llama-server --embedding ... -p 8084                           # embedder
eval/.venv/bin/python -c "from rag_mirror.rag_v2 import RagV2; RagV2().build_vectors()"
RESCATE_EVAL_SERVER_URL=http://127.0.0.1:8081 eval/.venv/bin/python \
  eval/harness/run_eval_v2.py --model gemma-4-e2b-q4km --tag wz-nb-oos
eval/.venv/bin/python eval/grading/grade_v4.py                 # corrected scores
```

Commits this session (all local): `dafc617`, `1ee997e`, `be0ec9c`,
`5e03d3b`, `c8eecd5`, `81b4d61`, `a24335f`.
