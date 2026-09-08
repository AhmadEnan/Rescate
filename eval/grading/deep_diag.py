import sys, json
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from pathlib import Path
import numpy as np
import urllib.request

def embed(text):
    req = urllib.request.Request("http://127.0.0.1:8084/v1/embeddings",
        data=json.dumps({"input": [text]}).encode(), headers={"Content-Type":"application/json"})
    return np.array(json.loads(urllib.request.urlopen(req, timeout=60).read())['data'][0]['embedding'])

SENT = json.load(open('/home/melezaly/Projects/Rescate/eval/rag_mirror/sentences.json'))
V = np.load('/home/melezaly/Projects/Rescate/eval/rag_mirror/vectors.npy')
Vn = V / np.maximum(np.linalg.norm(V, axis=1, keepdims=True), 1e-9)

for query, src in [("what to do when someone has a seizure", "06_neurological_emergencies_guideline"),
                   ("asthma attack inhaler not working", "03_breathing_chest_guideline")]:
    q = embed(query); q /= max(float(np.linalg.norm(q)), 1e-9)
    sims = Vn @ q
    order = np.argsort(sims)[::-1]
    pos_of = {int(i): rank + 1 for rank, i in enumerate(order)}
    target_ranks = sorted(pos_of[i] for i, s in enumerate(SENT) if (s['source'] == src or s['source'].startswith(src)))
    print(f"== {query!r} want {src[:35]}: best target rank = {target_ranks[0]} ({len(target_ranks)} target sents)")
    for i in order[:6]:
        s = SENT[int(i)]
        print(f"    [{pos_of[int(i)]:4}] {s['source'][:28]}: {s['text'][:70]}")
