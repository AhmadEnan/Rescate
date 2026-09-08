import json

d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__imp-v3.json'))
for t in d['transcripts']:
    mark = "PASS" if t['checks']['pass'] else "FAIL"
    print(f"[{mark}] {t['id']}")
    if not t['checks']['pass']:
        print("   fails:", t['checks']['soft_fails'] or t['checks']['hard_fails'])
    print("  ", t['answer'][:220].replace(chr(10), ' | '))
    print()
