import json, sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
rag = RagV2(mmr_lambda=0.5)
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
ctx = build_context_with_triage(rag, Q)
c = ctx["context"].lower()
print("injected sources:", ctx["triage_injected"])
print("ctx has 'weakness':", "weakness" in c, "| 'paralysis':", "paralysis" in c, "| 'one side':", "one side" in c)
# show the injected head of the context
print("--- context head ---")
print(ctx["context"][:600])
