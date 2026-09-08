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

# bge-m3 handles long input but llama-server batch is 512 tokens: chunk long
# sentences into <=400-char pieces and mean-pool pieces back to sentence vec.
def embed_sentence_smart(text, dim):
    pieces = [text[i:i+400] for i in range(0, len(text), 400)] or [text]
    vs = embed_batch(pieces)
    v = np.mean(vs, axis=0)
    return v / max(float(np.linalg.norm(v)), 1e-9)

texts = [s['text'] for s in SENT]
t0 = time.time()
vecs = []
buf, buf_idx = [], []
for i, t in enumerate(texts):
    pieces = [t[j:j+400] for j in range(0, len(t), 400)] or [t]
    buf.extend(pieces)
    buf_idx.append((i, len(pieces)))
    if len(buf) >= 48:
        vs = embed_batch(buf)
        p = 0
        for i0, n in buf_idx:
            v = np.mean(vs[p:p+n], axis=0)
            vecs.append(v / max(float(np.linalg.norm(v)), 1e-9))
            p += n
        buf, buf_idx = [], []
    if i % 1000 == 0:
        print(f'embedded {i}/{len(texts)}', flush=True)
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
