import json

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__wz-nb-oos.json'))
prev = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__ragv2-wz-nb.json'))
P = {t['id']: t for t in prev['transcripts']}
for t in d['transcripts']:
    if t['checks']['hard_fails'] and not P[t['id']]['checks']['hard_fails']:
        print("NEW HARD-FAIL:", t['id'], t['checks']['hard_fails'])
        print("   ", t['answer'][:180])
print()
oos = next(t for t in d['transcripts'] if t['id'] == 'ar-oos-dose')
print("ar-oos-dose now:", oos['checks'])
print(oos['answer'][:220])
