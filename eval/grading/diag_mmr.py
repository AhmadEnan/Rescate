"""Diagnose Dart vs Python MMR divergence precisely.

Dart: _133:20, _90:19, _2:32, _129:14, _2:0, _6:22, _44:18, _7:12
Py:   _133:20, _90:19, _7:20,  _2:32,  _2:0, _129:14, _44:18, _21:5

First two match. Divergence starts at #3: Python picked _7:20 (the burn
classification chunk) over _2:32. Both applied MMR with lambda 0.5...
difference is likely the candidate window: Python uses cand[:20] over a
40-candidate list ranked by score; Dart uses mmrTopN=40 too...

Actually: Dart's div uses average cosine to selected (div/selected.length),
Python uses MAX cosine. That's the bug — port exactly the Python semantics.
"""
import json, struct, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np

FIX = '/home/melezaly/Projects/Rescate/packages/ai_inference/test/rag_fixtures'
sents = json.load(open(f'{FIX}/fixture_sentences.json'))
bytes_ = open(f'{FIX}/fixture_vectors_q8.bin', 'rb').read()
rows, cols = struct.unpack('<II', bytes_[:8])
data = np.frombuffer(bytes_[8:8+rows*cols], dtype=np.int8).reshape(rows, cols)
scales = np.frombuffer(bytes_[8+rows*cols:8+rows*cols+rows*4], dtype='<f4')
Vq = data.astype(np.float32) * scales[:, None]
Vqn = Vq / np.maximum(np.linalg.norm(Vq, axis=1, keepdims=True), 1e-9)

def mmr_max(qv, top_k=8, mmr_top_n=40, lam=0.5):
    sims = Vqn @ qv
    cand = list(np.argsort(-sims)[:min(mmr_top_n, rows)])
    selected = []
    max_s = max(sims[cand]) if cand else 1e-9
    while cand and len(selected) < top_k:
        best, best_s = None, -1e9
        for i in cand[:20]:
            div = max(float(Vqn[i] @ Vqn[j]) for j in selected) if selected else 0.0
            s = lam * (sims[i] / max_s) - (1 - lam) * div
            if s > best_s:
                best_s, best = s, i
        selected.append(best)
        cand.remove(best)
    return [sents[int(i)]['i'].split('_chunk')[-1] for i in selected]

def mmr_avg(qv, top_k=8, mmr_top_n=40, lam=0.5):
    sims = Vqn @ qv
    cand = list(np.argsort(-sims)[:min(mmr_top_n, rows)])
    selected = []
    max_s = max(sims[cand]) if cand else 1e-9
    while cand and len(selected) < top_k:
        best, best_s = None, -1e9
        for i in cand[:20]:
            div = sum(float(Vqn[i] @ Vqn[j]) for j in selected) / len(selected) if selected else 0.0
            s = lam * (sims[i] / max_s) - (1 - lam) * div
            if s > best_s:
                best_s, best = s, i
        selected.append(best)
        cand.remove(best)
    return [sents[int(i)]['i'].split('_chunk')[-1] for i in selected]

exp = json.load(open(f'{FIX}/fixture_expected.json'))
qv = np.array(exp['queries'][0]['query_vec'], dtype=np.float32)
print('max-div:', mmr_max(qv)[:4])
print('avg-div:', mmr_avg(qv)[:4])
print('PY ref :', ['_133:20', '_90:19', '_7:20', '_2:32'])
