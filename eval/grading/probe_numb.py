import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2

v2 = RagV2(mmr_lambda=0.5)
q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
ctx = v2.build_context(q, top_k=16, max_tokens=1400)
print("sources:", ctx["sources"])
print("tokens:", ctx["tokens_est"])
print("top hits:")
for h in ctx["hits"][:6]:
    print("  -", h["source"][:30], "|", h["text"][:80])
c = ctx["context"].lower()
for m in ["stroke", "sudden", "weakness", "numbness", "one side", "face"]:
    print(f"{m!r} in ctx:", m in c)
