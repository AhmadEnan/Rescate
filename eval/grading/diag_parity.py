"""Diagnose q8 parity gap: Python exact re-simulation of the Dart rank path
against the fixture, to see if the Dart port or the fixture generation
differs (e.g. re-normalized q8 rows vs raw rows)."""
import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np

FIX = '/home/melezaly/Projects/Rescate/packages/ai_inference/test/rag_fixtures'
sents = json.load(open(f'{FIX}/fixture_sentences.json'))
exp = json.load(open(f'{FIX}/fixture_expected.json'))

bytes_ = open(f'{FIX}/fixture_vectors_q8.bin', 'rb').read()
import struct
rows, cols = struct.unpack('<II', bytes_[:8])
data = np.frombuffer(bytes_[8:8+rows*cols], dtype=np.int8).reshape(rows, cols)
scales = np.frombuffer(bytes_[8+rows*cols:8+rows*cols+rows*4], dtype='<f4')

# Dart semantics: dot(q, data_row) * scale  (NO re-normalization of the row)
Vq_dart = data.astype(np.float32) * scales[:, None]
# Python ground truth was f32 L2-normalized rows
Vq_norm = Vq_dart / np.maximum(np.linalg.norm(Vq_dart, axis=1, keepdims=True), 1e-9)

for q in exp['queries']:
    qv = np.array(q['query_vec'], dtype=np.float32)
    order_dart = np.argsort(Vq_dart @ qv)[::-1][:3]
    order_norm = np.argsort(Vq_norm @ qv)[::-1][:3]
    ids_dart = [sents[int(i)]['i'] for i in order_dart]
    ids_norm = [sents[int(i)]['i'] for i in order_norm]
    match_dart = ids_dart == q['expected_ids'][:3]
    match_norm = ids_norm == q['expected_ids'][:3]
    print(f"q={q['query'][:30]!r} dart-exact={match_dart} renorm={match_norm}")
    if not match_dart:
        print("   dart top3:", [i.split('_chunk')[-1] for i in ids_dart])
        print("   want top3:", [i.split('_chunk')[-1] for i in q['expected_ids'][:3]])
