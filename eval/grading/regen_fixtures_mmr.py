"""Simulate the EXACT Dart rank path in Python, including MMR re-rank,
to find where Dart diverges from the fixture generation (which didn't
apply MMR). The fixture 'expected_ids' are raw-cosine order, but Dart
applies MMR after ranking - top-3 post-MMR differs. Regenerate fixtures
through the MMR path so parity is meaningful."""
import json, struct, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np

FIX = '/home/melezaly/Projects/Rescate/packages/ai_inference/test/rag_fixtures'
sents = json.load(open(f'{FIX}/fixture_sentences.json'))
exp = json.load(open(f'{FIX}/fixture_expected.json'))

bytes_ = open(f'{FIX}/fixture_vectors_q8.bin', 'rb').read()
rows, cols = struct.unpack('<II', bytes_[:8])
data = np.frombuffer(bytes_[8:8+rows*cols], dtype=np.int8).reshape(rows, cols)
scales = np.frombuffer(bytes_[8+rows*cols:8+rows*cols+rows*4], dtype='<f4')
Vq = data.astype(np.float32) * scales[:, None]
Vqn = Vq / np.maximum(np.linalg.norm(Vq, axis=1, keepdims=True), 1e-9)

def mmr_rerank(qv, top_k=8, mmr_top_n=40, lam=0.5):
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
    return selected

for q in exp['queries']:
    qv = np.array(q['query_vec'], dtype=np.float32)
    raw = np.argsort(-(Vqn @ qv))[:8]
    mmr = mmr_rerank(qv)
    q['expected_ids_raw'] = [sents[int(i)]['i'] for i in raw]
    q['expected_ids'] = [sents[int(i)]['i'] for i in mmr]
    print(q['query'][:28])
    print('  raw:', [i.split('_chunk')[-1] for i in q['expected_ids_raw'][:3]])
    print('  mmr:', [i.split('_chunk')[-1] for i in q['expected_ids'][:3]])

json.dump(exp, open(f'{FIX}/fixture_expected.json', 'w'))
print('updated fixture_expected.json with post-MMR order')
