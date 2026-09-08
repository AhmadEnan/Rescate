"""Regenerate fixture_expected.json from q8 dequantized semantics (the Dart
path) instead of f32 full-index semantics. Same queries; expected ids computed
with rows* scales (no renorm) so Dart matches exactly. Ties broken identically:
Python argsort stable-descending == Dart sort desc (same key values)."""
import json, struct, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
import numpy as np
import urllib.request

FIX = '/home/melezaly/Projects/Rescate/packages/ai_inference/test/rag_fixtures'
sents = json.load(open(f'{FIX}/fixture_sentences.json'))
exp = json.load(open(f'{FIX}/fixture_expected.json'))

bytes_ = open(f'{FIX}/fixture_vectors_q8.bin', 'rb').read()
rows, cols = struct.unpack('<II', bytes_[:8])
data = np.frombuffer(bytes_[8:8+rows*cols], dtype=np.int8).reshape(rows, cols)
scales = np.frombuffer(bytes_[8+rows*cols:8+rows*cols+rows*4], dtype='<f4')
Vq = data.astype(np.float32) * scales[:, None]

for q in exp['queries']:
    qv = np.array(q['query_vec'], dtype=np.float32)
    order = np.argsort(-(Vq @ qv))[:8]
    q['expected_ids'] = [sents[int(i)]['i'] for i in order]

json.dump(exp, open(f'{FIX}/fixture_expected.json', 'w'))
for q in exp['queries']:
    print(q['query'][:30], '->', q['expected_ids'][0].split('_chunk')[-1])
