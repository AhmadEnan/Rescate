import json, sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
rag = RagV2(mmr_lambda=0.5)
# Widen the anchor retrieval so the full stroke-signs text makes it in
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
ctx = build_context_with_triage(rag, Q, top_k=16, max_tokens=1600, neighbors=1)
c = ctx["context"].lower()
checks = {
    "stroke word": "stroke" in c,
    "facial droop": "facial droop" in c,
    "weakness/paralysis": "weakness" in c or "paralysis" in c,
    "one side": "one side" in c or "only one" in c,
    "escalation frame present": bool(ctx["escalation_frame"]),
}
print(checks)
