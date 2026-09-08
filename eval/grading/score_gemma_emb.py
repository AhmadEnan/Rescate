"""Empirical test: can Gemma-4-E2B double as the embedder?

Scores last-token pooled embeddings on the 48-case retrieval suite, same
protocol as the bge-m3 experiment. Gemma emits 1536-dim; our stored vectors
are Qwen3 1024-dim, so this rebuilds its own matrix and compares quality.
Also measures query latency (this is a 2B model, not a 0.6B).
"""
import json, sys, time
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request

SENT = json.load(open('/home/melezaly/Projects/Rescate/eval/rag_mirror/sentences.json'))
cases = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/retrieval_suite_v2.json'))['cases']
PORT = '8086'

def embed_batch(texts):
    req = urllib.request.Request(f'http://127.0.0.1:{PORT}/v1/embeddings',
        data=json.dumps({'input': texts}).encode(), headers={'Content-Type': 'application/json'})
    r = json.loads(urllib.request.urlopen(req, timeout=900).read())
    return [np.array(d['embedding'], dtype=np.float32) for d in sorted(r['data'], key=lambda x: x['index'])]

texts = [s['text'] for s in SENT]
print(f'embedding {len(texts)} sentences with Gemma-4-E2B last-token pooling...', flush=True)
t0 = time.time()
vecs = []
buf, buf_idx = [], []
for i, t in enumerate(texts):
    pieces = [t[j:j+400] for j in range(0, len(t), 400)] or [t]
    buf.extend(pieces)
    buf_idx.append((i, len(pieces)))
    if len(buf) >= 24:
        vs = embed_batch(buf)
        p = 0
        for i0, n in buf_idx:
            v = np.mean(vs[p:p+n], axis=0)
            vecs.append(v / max(float(np.linalg.norm(v)), 1e-9))
            p += n
        buf, buf_idx = [], []
    if i % 500 == 0:
        el = time.time() - t0
        eta = el / (i + 1) * (len(texts) - i - 1)
        print(f'{i}/{len(texts)} elapsed={el/60:.0f}m eta={eta/60:.0f}m', flush=True)
if buf:
    vs = embed_batch(buf)
    p = 0
    for i0, n in buf_idx:
        v = np.mean(vs[p:p+n], axis=0)
        vecs.append(v / max(float(np.linalg.norm(v)), 1e-9))
        p += n
V = np.vstack(vecs)
build_s = time.time() - t0
print(f'build took {build_s/60:.1f} min, dim={V.shape[1]}', flush=True)

def src_match(s, t): return s == t or s.startswith(t)
hit = aic = 0
lats = []
for c in cases:
    t1 = time.time()
    qv = embed_batch([c['query']])[0]
    lats.append(time.time() - t1)
    qv /= max(float(np.linalg.norm(qv)), 1e-9)
    sims = V @ qv
    order = np.argsort(-sims)[:32]
    acc = [c['source'], *c.get('alternative_sources', [])]
    if any(src_match(SENT[int(i)]['source'], s) for i in order for s in acc):
        hit += 1
    ctx_txt = ' '.join(SENT[int(i)]['text'] for i in order[:16]).lower()
    if c['answer_marker'].lower() in ctx_txt:
        aic += 1
import statistics
print(f'RESULT gemma-e2b-emb: hit={hit}/48 ans-in-ctx={aic}/48 '
      f'q-lat-med={statistics.median(lats)*1000:.0f}ms')
