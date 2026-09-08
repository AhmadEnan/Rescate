import json, re, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from grading.grade_v4 import negation_scoped_hard
from harness.run_eval import check_case

ds = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/bilingual_qa_v1.json'))
by_id = {c['id']: c for c in ds['cases']}

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/qwen3.5-2b-q3__wz-final.json'))
passed = hard = 0
for t in d['transcripts']:
    case = by_id[t['id']]
    checks = dict(check_case(case, t['answer']))
    real = negation_scoped_hard(case, t['answer'])
    checks['hard_fails'] = real
    if real: checks['pass'] = False
    passed += checks['pass']; hard += bool(real)
print(f"qwen3.5-2b-q3 wz-final (grader v4): pass={passed}/15, hard={hard}")

# breakdown of the 4 hard fails
for t in d['transcripts']:
    case = by_id[t['id']]
    real = negation_scoped_hard(case, t['answer'])
    if real:
        print(f"  HARD: {t['id']} {real}")
        print("   ans:", t['answer'][:150])
