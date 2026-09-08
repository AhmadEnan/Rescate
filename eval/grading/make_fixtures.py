"""Generate Dart test fixtures from the live rag_v2 index.

Produces (in packages/ai_inference/test/rag_fixtures/):
- fixture_sentences.json: 64-sentence slice (with their true ids)
- fixture_vectors_q8.bin: their q8 vectors, same bin format as the real asset
- fixture_expected.json: for 4 probe queries, the embedded query vec +
  expected top-8 sentence ids as ranked by the Python pipeline (ground truth)
"""
import json
import struct
import sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request

SENT = json.load(open('/home/melezaly/Projects/Rescate/eval/rag_mirror/sentences.json'))
V8 = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8.npy')
SC = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8_scale.npy')

# deterministic slice: every 118th sentence -> 64 units
idxs = list(range(0, len(SENT), 118))[:64]
slice_sents = [SENT[i] for i in idxs]
id_to_row = {s['id']: i for i, s in enumerate(SENT)}

OUT = '/home/melezaly/Projects/Rescate/packages/ai_inference/test/rag_fixtures'
import os
os.makedirs(OUT, exist_ok=True)

json.dump(
    [{'i': s['id'], 'c': s['chunk_id'], 's': s['source'], 'p': s.get('pos', 0), 't': s['text']} for s in slice_sents],
    open(f'{OUT}/fixture_sentences.json', 'w'), ensure_ascii=False, separators=(',', ':'))

# fixture vectors: subset of the global q8 matrix (renumbered rows)
sub8 = V8[idxs]
subSC = SC[idxs]
with open(f'{OUT}/fixture_vectors_q8.bin', 'wb') as f:
    f.write(struct.pack('<II', len(idxs), V8.shape[1]))
    f.write(sub8.tobytes())
    f.write(subSC.astype('<f4').tobytes())

def embed(text):
    req = urllib.request.Request("http://127.0.0.1:8084/v1/embeddings",
        data=json.dumps({"input": [text]}).encode(), headers={"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=60).read())
    v = np.array(sorted(r['data'], key=lambda x: x['index'])[0]['embedding'], dtype=np.float32)
    return (v / max(float(np.linalg.norm(v)), 1e-9)).tolist()

# ground-truth rankings via the full-index f32 pipeline semantics
V = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors.npy')
Vn = V / np.maximum(np.linalg.norm(V, axis=1, keepdims=True), 1e-9)
SLICE_Vn = Vn[idxs]

queries = [
    ("burn second degree cool water", "burn_classification_guideline_v2 (1)"),
    ("severe bleeding pressure tourniquet", "First_Aid_Guide"),
    ("choking cannot breathe", "First_Aid_Guide"),
    ("النزيف الغزير ضغط", "First_Aid_Guide"),
]
out = {"queries": []}
for q, _src in queries:
    req = urllib.request.Request("http://127.0.0.1:8084/v1/embeddings",
        data=json.dumps({"input": [q]}).encode(), headers={"Content-Type": "application/json"})
    v = np.array(json.loads(urllib.request.urlopen(req, timeout=60).read())['data'][0]['embedding'], dtype=np.float32)
    v /= max(float(np.linalg.norm(v)), 1e-9)
    sims = SLICE_Vn @ v
    order = np.argsort(sims)[::-1][:8]
    expected_ids = [slice_sents[int(i)]['id'] for i in order]
    out["queries"].append({"query": q, "query_vec": v.tolist(), "expected_ids": expected_ids})
    print(f"{q!r}: top-1 = {expected_ids[0][:40]}")

json.dump(out, open(f'{OUT}/fixture_expected.json', 'w'))
print("fixtures written to", OUT)
