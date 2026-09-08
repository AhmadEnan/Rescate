import json, sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
rag = RagV2(mmr_lambda=0.5)
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
ctx = build_context_with_triage(rag, Q)
print("triage:", ctx["triage"])
print("injected:", ctx["triage_injected"])
print("frame:", ctx["escalation_frame"][:90])
c = ctx["context"].lower()
print("stroke content now in ctx:", ("paralysis" in c or "weakness" in c) and ("one side" in c or "cva" in c or "stroke" in c))
