import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2

v2 = RagV2(mmr_lambda=0.5)
probes = [
    ("what is the correct compression rate and depth for adult CPR", ["30", "recovery position", "elevate the legs", "call emergency"]),
    ("seizure recovery position after convulsion stops", ["recovery position"]),
    ("severe bleeding elevate legs direct pressure call emergency", ["elevate", "call emergency", "911"]),
]
for q, markers in probes:
    ctx = v2.build_context(q, top_k=16, max_tokens=1400)
    print(f"Q: {q}")
    for m in markers:
        print(f"   {m!r} in context: {m.lower() in ctx['context'].lower()}")
    print()
