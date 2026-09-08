"""Measure retrieval quality with q8 vectors vs f32 on the 48-case suite."""
import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request

from rag_mirror.rag_v2 import RagV2, SENTENCES

def embed(text):
    req = urllib.request.Request("http://127.0.0.1:8084/v1/embeddings",
        data=json.dumps({"input": [text]}).encode(), headers={"Content-Type": "application/json"})
    return np.array(json.loads(urllib.request.urlopen(req, timeout=60).read())['data'][0]['embedding'])

V8 = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8.npy')
SC = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8_scale.npy')
Vq = V8.astype(np.float32) * SC
Vq /= np.maximum(np.linalg.norm(Vq, axis=1, keepdims=True), 1e-9)

cases = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/retrieval_suite_v2.json'))['cases']
def src_match(s, t): return s == t or s.startswith(t)

hit_f32 = hit_q8 = aic_f32 = aic_q8 = 0
for c in cases:
    # f32 (production path)
    ctx = rag_ctx = None
    rag = RagV2(mmr_lambda=0.5)
    ctx = rag.build_context(c['query'], top_k=24, max_tokens=1400, neighbors=1)
    acc = [c['source'], *c.get('alternative_sources', [])]
    if any(src_match(h['source'], s) for h in ctx['hits'] for s in acc):
        hit_f32 += 1
    if c['answer_marker'].lower() in ctx['context'].lower():
        aic_f32 += 1
    # q8 path: swap the normalized matrix, rerun dense+MMR only
    qv = embed(c['query']); qv /= max(float(np.linalg.norm(qv)), 1e-9)
    sims = Vq @ qv
    idx = np.argsort(sims)[::-1][:40]
    dense_hits = [(int(i), float(sims[i])) for i in idx if sims[i] > 0.25]
    # replicate RRF with lexical via rag internals: use retrieve then override dense scores
    # simpler: rank by dense only (lexical weight small at this suite), check hit
    rrf = {}
    for rank, (i, _s) in enumerate(dense_hits):
        rrf[i] = rrf.get(i, 0) + 0.62 / (60 + rank + 1)
    cand = sorted(rrf, key=lambda i: rrf[i], reverse=True)[:24]
    if any(src_match(SENTENCES[i]['source'], s) for i in cand[:24] for s in acc for i in [i]):
        hit_q8 += 1
    txt = " ".join(SENTENCES[i]['text'] for i in cand[:16]).lower()
    if c['answer_marker'].lower() in txt:
        aic_q8 += 1

print(f"f32: hit={hit_f32}/48 ans-in-ctx={aic_f32}/48")
print(f"q8 : hit={hit_q8}/48 ans-in-ctx={aic_q8}/48 (dense-only approx)")
