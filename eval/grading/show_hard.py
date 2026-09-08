import json, re, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from harness.run_eval import check_case

ds = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/bilingual_qa_v1.json'))
by_id = {c['id']: c for c in ds['cases']}

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__wz-nb-oos.json'))
for t in d['transcripts']:
    if t['checks']['hard_fails']:
        case = by_id[t['id']]
        print("==", t['id'], t['checks']['hard_fails'])
        for i, s in enumerate(re.split(r'(?<=[.!?])\s+', t['answer'])):
            for grp in case.get('must_not_contain_any', []):
                for m in grp:
                    if m.lower() in s.lower():
                        print(f"   sentence {i}: {s!r}")
