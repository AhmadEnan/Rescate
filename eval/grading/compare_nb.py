import json

a = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__ragv2-warzone.json'))
b = json.load(open('/home/melezaly/Projects/Rescate/eval/results/gemma-4-e2b-q4km__ragv2-wz-nb.json'))
A = {t['id']: t for t in a['transcripts']}
B = {t['id']: t for t in b['transcripts']}
for cid in A:
    if A[cid]['checks']['pass'] != B[cid]['checks']['pass']:
        print(f"{cid:28} {'PASS' if A[cid]['checks']['pass'] else 'FAIL'} -> {'PASS' if B[cid]['checks']['pass'] else 'FAIL'}")
        if not B[cid]['checks']['pass']:
            print('   now failing:', B[cid]['checks']['soft_fails'] or B[cid]['checks']['hard_fails'])
print("\nseizure answer (neighbors on):")
print(B['en-seizure-position']['answer'][:260])
