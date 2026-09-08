import json, re, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__wz-nb-oos.json'))
for t in d['transcripts']:
    if t['checks']['hard_fails']:
        print(t['id'], t['checks']['hard_fails'])
