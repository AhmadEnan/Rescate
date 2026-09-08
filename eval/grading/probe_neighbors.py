import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2

v2 = RagV2(mmr_lambda=0.5)

# A) phase-2 probe: does neighbor expansion surface the seizure aftercare?
ctx = v2.build_context("someone is having a seizure what do I do", top_k=16, max_tokens=1400, neighbors=2)
print("seizure: 'recovery position' in ctx:", "recovery position" in ctx["context"].lower())
ctx0 = v2.build_context("someone is having a seizure what do I do", top_k=16, max_tokens=1400, neighbors=0)
print("seizure (no neighbors):", "recovery position" in ctx0["context"].lower())

# B) CPR probe with neighbors: does 30:2 ride along?
ctx2 = v2.build_context("how to do CPR on an adult", top_k=16, max_tokens=1400, neighbors=2)
print("cpr: '30 compressions' in ctx:", "30 compressions" in ctx2["context"].lower())

# C) bleeding probe: emergency-call phrasing
ctx3 = v2.build_context("severe bleeding from a wound immediate steps", top_k=16, max_tokens=1400, neighbors=2)
c = ctx3["context"].lower()
print("bleeding: 'emergency'/'tourniquet':", "emergency" in c or "tourniquet" in c)

# D) suite sanity: re-score 48 cases with neighbors=2 (hit only, fast subset check)
cases = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/retrieval_suite_v2.json'))['cases']
def source_matches(s, t): return s == t or s.startswith(t)
hit = 0; aic = 0
for case in cases:
    cc = v2.build_context(case['query'], top_k=24, max_tokens=1400, neighbors=2)
    accepted = [case['source'], *case.get('alternative_sources', [])]
    if any(source_matches(h['source'], s) for h in cc['hits'] for s in accepted):
        hit += 1
    if case['answer_marker'].lower() in cc['context'].lower():
        aic += 1
print(f"suite v2 (neighbors=2): hit={hit}/{len(cases)}, answer_in_context={aic}/{len(cases)}")
