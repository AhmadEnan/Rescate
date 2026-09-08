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
    r = json.loads(urllib.request.urlopen(req, timeout=600).read())
    return [np.array(d['embedding'], dtype=np.float32) for d in sorted(r['data'], key=lambda x: x['index'])]

texts = [s['text'] for s in SENT]
t0 = time.time()
vecs = []
for i in range(0, len(texts), 64):
    vecs.extend(embed_batch(texts[i:i+64]))
    if (i // 64) % 25 == 0:
        print(f'embedded {i+64}/{len(texts)}', flush=True)
V = np.vstack(vecs)
V = V / np.maximum(np.linalg.norm(V, axis=1, keepdims=True), 1e-9)
build_s = time.time() - t0
print(f'build took {build_s/60:.1f} min, dim={V.shape[1]}')

def src_match(s, t): return s == t or s.startswith(t)
hit = aic = 0
t0 = time.time()
for c in cases:
    qv = embed_batch([c['query']])[0]
    qv /= max(float(np.linalg.norm(qv)), 1e-9)
    sims = V @ qv
    order = np.argsort(-sims)[:32]
    acc = [c['source'], *c.get('alternative_sources', [])]
    if any(src_match(SENT[int(i)]['source'], s) for i in order for s in acc):
        hit += 1
    ctx_txt = ' '.join(SENT[int(i)]['text'] for i in order[:16]).lower()
    if c['answer_marker'].lower() in ctx_txt:
        aic += 1
lat = (time.time() - t0) / len(cases) * 1000
print(f'RESULT bge-m3-Q4: hit={hit}/48 ans-in-ctx={aic}/48 q-lat={lat:.0f}ms')
np.save('/tmp/bge_m3_vecs.npy', V[:100])  # small sample only, not the full thing
