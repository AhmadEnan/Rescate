import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2

# corpus-verify the implicit danger-sign claims before writing cases
v2 = RagV2(mmr_lambda=0.5)
probes = {
 "imp-painless-burn": ("i think i burned my hand, it looks really bad but it doesnt hurt that much",
                       ["third-degree", "third degree", "deep", "charred", "white"]),
 "imp-nuro-poison":   ("my toddler swallowed some of his grandmas heart pills and seems fine now",
                       ["medical", "hospital", "poison", "urgent", "emergency"]),
 "imp-abdominal":     ("he got hit in the stomach hard, he feels okay but keeps vomiting",
                       ["internal", "serious", "medical", "urgent", "emergency"]),
 "imp-slow-bleed":    ("there is blood soaking through the bandage on my friends arm",
                       ["tourniquet", "another", "on top", "add", "more", "call"]),
}
for cid, (q, markers) in probes.items():
    ctx = v2.build_context(q, top_k=16, max_tokens=1400)
    c = ctx["context"].lower()
    found = [m for m in markers if m in c]
    print(f"{cid}: retrievable markers: {found} | ctx-tok={ctx['tokens_est']}")
