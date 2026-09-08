"""Download the two smallest credible multilingual embedders and score them
against the CURRENT 7,535-sentence q8 index on the 48-case retrieval suite.

Note: vectors.npy was built with Qwen3-Embedding-0.6B; a different embedder
needs its own vector matrix (dim mismatch). So for candidates we:
1. embed all 7,535 sentences + all queries with the candidate model
2. score hit@k / answer-in-context
3. compare against the Qwen3 baseline (45/48 hit, 38/48 in-ctx)

Only pass/fail summary per model; this is a scale experiment, not a ship.
"""
import json, sys, time
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request
import subprocess, os
from pathlib import Path

Q8_PATH = '/home/melezaly/Projects/Rescate/eval/models/embeddings/candidates'
os.makedirs(Q8_PATH, exist_ok=True)
SENT = json.load(open('/home/melezaly/Projects/Rescate/eval/rag_mirror/sentences.json'))
cases = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/retrieval_suite_v2.json'))['cases']

MODEL = sys.argv[1]
FILE = sys.argv[2]
PORT = sys.argv[3]
DIM = int(sys.argv[4])
TAG = sys.argv[5]

# 1. download
target = f'{Q8_PATH}/{TAG}.gguf'
if not os.path.exists(target):
    url = f'https://huggingface.co/{MODEL}/resolve/main/{FILE}'
    subprocess.run(['curl', '-sL', '-o', target, url], check=True)
print(f'{TAG}: {(os.path.getsize(target)/1e6):.0f}MB downloaded', flush=True)

# 2. serve (caller must start llama-server on PORT with this model before
#    calling; we just probe health)
for _ in range(60):
    try:
        urllib.request.urlopen(f'http://127.0.0.1:{PORT}/health', timeout=2)
        break
    except Exception:
        time.sleep(2)

def embed_batch(texts, port):
    req = urllib.request.Request(f'http://127.0.0.1:{port}/v1/embeddings',
        data=json.dumps({'input': texts}).encode(), headers={'Content-Type': 'application/json'})
    r = json.loads(urllib.request.urlopen(req, timeout=600).read())
    return [np.array(d['embedding'], dtype=np.float32) for d in sorted(r['data'], key=lambda x: x['index'])]

# 3. embed all sentences
texts = [s['text'] for s in SENT]
t0 = time.time()
vecs = []
for i in range(0, len(texts), 64):
    vecs.extend(embed_batch(texts[i:i+64], PORT))
    if (i // 64) % 25 == 0:
        print(f'  {TAG}: embedded {i+64}/{len(texts)}', flush=True)
V = np.vstack(vecs)
V = V / np.maximum(np.linalg.norm(V, axis=1, keepdims=True), 1e-9)
build_s = time.time() - t0

# 4. score
def src_match(s, t): return s == t or s.startswith(t)
hit = aic = 0
t0 = time.time()
for c in cases:
    qv = embed_batch([c['query']], PORT)[0]
    qv /= max(float(np.linalg.norm(qv)), 1e-9)
    sims = V @ qv
    order = np.argsort(-sims)[:32]
    acc = [c['source'], *c.get('alternative_sources', [])]
    if any(src_match(SENT[int(i)]['source'], s) for i in order for s in acc):
        hit += 1
    ctx_txt = ' '.join(SENT[int(i)]['text'] for i in order[:16]).lower()
    if c['answer_marker'].lower() in ctx_txt:
        aic += 1
lat_ms = (time.time() - t0) / len(cases) * 1000
print(f'RESULT {TAG}: hit={hit}/48 ans-in-ctx={aic}/48 '
      f'build={build_s/60:.1f}min q-lat={lat_ms:.0f}ms dim={DIM} '
      f'size={(os.path.getsize(target)/1e6):.0f}MB')
