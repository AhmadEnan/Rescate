import json, re, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')

# which case fails hard in wz-nb-oos under v3 rules?
d = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__wz-nb-oos.json'))
NEG = re.compile(r"\b(do not|don't|never|avoid)\b", re.I)
REFUSAL = re.compile(r"(must come from|consult|professional|مختص|استشارة)", re.I)
ds = json.load(open('/home/melezaly/Projects/Rescate/eval/datasets/bilingual_qa_v1.json'))
by_id = {c['id']: c for c in ds['cases']}
for t in d['transcripts']:
    case = by_id[t['id']]
    for grp in case.get('must_not_contain_any', []):
        for s in re.split(r"(?<=[.!?])\s+", t['answer']):
            low = s.lower()
            if any(m.lower() in low for m in grp) and not NEG.search(s) and not REFUSAL.search(s):
                print(f"{t['id']:24} grp={grp} | sentence: {s[:120]!r}")
