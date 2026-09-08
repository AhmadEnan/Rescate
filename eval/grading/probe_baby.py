import sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
Q = "ابني الرضيع محتاج ياكل بس مفيش لبن ممكن ااكله ايه"
rag = RagV2(mmr_lambda=0.5)

print("=== triage on query ===")
from rag_mirror.triage import triage
print(triage(Q))

ctx = build_context_with_triage(rag, Q, top_k=16, max_tokens=1400)
print("sources:", ctx["sources"])
print("top hits:")
for h in ctx["hits"][:8]:
    print("  -", h["source"][:32], "|", h["text"][:90])
