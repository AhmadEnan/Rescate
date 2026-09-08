import json, sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.legacy_rag import SYSTEM_PROMPT_EN
from rag_mirror.rag_v2 import RagV2
from harness.discord_bridge import build_backend, strip_think
from harness.run_eval_v2 import build_gemma_raw

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8081")
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"

rag = RagV2(mmr_lambda=0.5)
ctx = rag.build_context(Q, top_k=16, max_tokens=1400)
backend = build_backend("gemma-4-e2b-q4km", None)
prompt = build_gemma_raw(ctx["context"], Q, arabic=True)
gen = backend.generate(prompt, max_tokens=400, use_chat=False)
print(strip_think(gen.text).strip())
