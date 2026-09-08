#!/usr/bin/env python3
"""Live A/B: send Sheref's exact message to E2B-Q4 and Qwen3.5-Q3 through
the final warzone pipeline (rag_v2 + neighbors + OOS guard prompt)."""
import json, sys, time
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')

from rag_mirror.legacy_rag import SYSTEM_PROMPT_EN
from rag_mirror.rag_v2 import RagV2, is_arabic
from harness.discord_bridge import build_backend, strip_think

Q = "i think i burned my hand, it looks really bad but it doesnt hurt that much"

rag = RagV2(mmr_lambda=0.5)
ctx = rag.build_context(Q, top_k=16, max_tokens=1400)

user = f"MEDICAL REFERENCE:\n{ctx['context']}\n\nQUESTION: {Q}"

print("=== retrieved sources ===")
print(ctx["sources"])
print("hits:", [(h["source"][:28], h["text"][:60]) for h in ctx["hits"][:4]])
print()

for model in ["gemma-4-e2b-q4km", "qwen3.5-2b-q3"]:
    import os
    os.environ["RESCATE_EVAL_SERVER_URL"] = "http://127.0.0.1:8081"
    backend = build_backend(model, None)
    t0 = time.time()
    if "gemma" in model:
        # raw Gemma-4 template path, same as run_eval_v2
        from harness.run_eval_v2 import build_gemma_raw
        prompt = build_gemma_raw(ctx["context"], Q, False)
        gen = backend.generate(prompt, max_tokens=400, use_chat=False)
    else:
        gen = backend.generate(user, max_tokens=400, system_prompt=SYSTEM_PROMPT_EN,
                               use_chat=True, enable_thinking=False)
    dt = time.time() - t0
    ans = strip_think(gen.text).strip()
    print(f"########## {model} ({gen.generated_tokens} tok, {dt:.0f}s) ##########")
    print(ans)
    print()
    sys.stdout.flush()
