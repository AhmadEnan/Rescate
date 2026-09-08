import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2

v2 = RagV2(mmr_lambda=0.5)
q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
# where does 'numbness' come from?
ctx = v2.build_context(q, top_k=24, max_tokens=2000)
for h in ctx["hits"]:
    if "numbn" in h["text"].lower():
        print("HIT:", h["source"][:30], "|", h["text"][:200])
# also: what does the stroke section look like when queried directly?
ctx2 = v2.build_context("sudden weakness or numbness on one side of the body stroke signs", top_k=8, max_tokens=800)
print()
print("stroke query sources:", ctx2["sources"])
print(ctx2["context"][:400])
