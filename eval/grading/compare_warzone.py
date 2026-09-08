import json

d_old = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__ragv2.json'))
d_new = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__ragv2-warzone.json'))

old = {t['id']: t for t in d_old['transcripts']}
new = {t['id']: t for t in d_new['transcripts']}

changed = []
for cid in old:
    o, n = old[cid]['checks'], new[cid]['checks']
    if o['pass'] != n['pass']:
        changed.append((cid, 'PASS' if n['pass'] else 'FAIL', 'PASS' if o['pass'] else 'FAIL'))

print("Changed verdicts (new vs old):")
for cid, n, o in changed:
    print(f"  {cid:28} {o} -> {n}")

print("\n=== ar-bleeding NEW ===")
print(new['ar-bleeding']['answer'][:300])
print("\n=== en-bleeding-severe NEW ===")
print(new['en-bleeding-severe']['answer'][:300])
