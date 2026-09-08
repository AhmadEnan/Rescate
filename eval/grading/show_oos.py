import json

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__wz-nb-oos.json'))
for t in d['transcripts']:
    if t['id'] in ('en-burn-degrees', 'en-oos-antibiotics'):
        print("==", t['id'], t['checks']['hard_fails'])
        print(t['answer'])
        print()
