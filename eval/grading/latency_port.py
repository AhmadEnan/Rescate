"""Port-budget measurement: simulate phone-CPU latency for the q8 pipeline.

- query embedding cost: measured on this 2-core VM (proxy for 2 big phone cores)
- cosine scan: numpy on VM; Dart on phone with Float32x4 SIMD is comparable
- outputs the Dart-port data contract
"""
import json, sys, time
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request

def embed(texts):
    req = urllib.request.Request("http://127.0.0.1:8084/v1/embeddings",
        data=json.dumps({"input": texts}).encode(), headers={"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=60).read())
    return [np.array(d['embedding'], dtype=np.float32) for d in sorted(r['data'], key=lambda x: x['index'])]

V8 = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8.npy')
SC = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors_q8_scale.npy')
Vq = V8.astype(np.float32) * SC
Vq /= np.maximum(np.linalg.norm(Vq, axis=1, keepdims=True), 1e-9)

# query embed latency (single, server roundtrip incl. tokenization)
t0 = time.time()
for _ in range(5):
    embed(["انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"])
emb_ms = (time.time() - t0) / 5 * 1000
print(f"query embedding roundtrip: {emb_ms:.0f} ms (VM, includes HTTP+tokenize)")

# cosine scan latency
qv = embed(["test"])[0]; qv /= max(float(np.linalg.norm(qv)), 1e-9)
t0 = time.time()
for _ in range(20):
    sims = Vq @ qv
    top = np.argsort(sims)[::-1][:24]
scan_ms = (time.time() - t0) / 20 * 1000
print(f"cosine scan 7535x1024 + argsort: {scan_ms:.1f} ms (numpy)")
print(f"total retrieval budget on phone (Dart SIMD, est): {emb_ms + scan_ms*2:.0f}-{(emb_ms+scan_ms*2)*2:.0f} ms")
