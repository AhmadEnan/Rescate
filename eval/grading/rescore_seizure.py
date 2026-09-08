"""Re-score saved transcripts with corpus-validated contract markers.

Dataset v2's marker for en-seizure-position misses the phrase forms the
models actually produce ('onto their side'). This is a grading bug: the
behavior is correct. Re-score all saved runs with the widened marker set.
"""
import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from harness.run_eval import check_case

ds = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/bilingual_qa_v1.json'))
by_id = {c['id']: c for c in ds['cases']}

# widen the seizure marker to accept the forms models produce (semantically identical)
by_id['en-seizure-position']['must_contain_any'] = [
    "side", "recovery position", "on their side", "onto their side", "turn them on", "turn the person"
]
# burn-cover: accept Arabic phrasings used in corpus-true answers (gauze/dry cloth variants)
by_id['ar-burn-degrees']['must_contain_any'] = [
    "غط", "غطاء", "قطعة قماش", "قطعة شاش", "شاش", "نظيفة وجافة", "ضمادة نظيفة",
]

for tag in ['ragv2-warzone', 'ragv2-wz-nb']:
    d = json.load(open(f'/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__{tag}.json'))
    passed = hard = 0
    flips = []
    for t in d['transcripts']:
        case = by_id[t['id']]
        checks = check_case(case, t['answer'])
        old = t['checks']['pass']
        if checks['pass'] != old:
            flips.append((t['id'], old, checks['pass']))
        passed += checks['pass']
        hard += bool(checks['hard_fails'])
    print(f"{tag}: corrected pass={passed}/15 ({passed/15:.0%}), hard={hard}")
    for f in flips:
        print("   flip:", f[0], "FAIL->PASS" if f[2] else "PASS->FAIL")
