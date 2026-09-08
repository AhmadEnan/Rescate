"""Verify the red-flag triage layer: the numb-hand query, paraphrases,
near-miss negatives, and force-injection behavior."""
import json, sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.triage import triage, escalation_frame
from rag_mirror.rag_v2 import RagV2

# 1) lexicon coverage: the original + paraphrases
positives = [
    ("انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها", "stroke"),
    ("صحيت النهارده لاقيت رجليي مش معايا", "stroke"),
    ("my hand is numb and I can't feel it since I woke up", "stroke"),
    ("my dad's face is drooping and his speech is slurred", "stroke"),
    ("my toddler swallowed some pills and seems fine", "ingestion"),
    ("ابني ابتلع حبوب", "ingestion"),
    ("blood is soaking through the bandage", "uncontrolled_bleeding"),
    ("الدم مش بيقف", "uncontrolled_bleeding"),
    ("he can't breathe", "airway_breathing"),
    ("مش قادر يتنفس", "airway_breathing"),
    ("i found him unconscious on the floor", "unconscious"),
    ("هو فاقد الوعي", "unconscious"),
    ("he fell down the stairs and wants to sleep", "head_trauma"),
    ("my hand is burned and looks bad but doesnt hurt", "severe_burn"),
]
negatives = [
    ("how do I treat a blister from hiking", None),
    ("what should be in a first aid kit", None),
    ("best way to remove a splinter", None),
    ("ازاي اعالج لسعة نحل بسيطة", None),
]
fails = 0
for q, want in positives:
    hits = [h.flag_id for h in triage(q)]
    ok = want in hits
    if not ok:
        fails += 1
    print(f"{'OK ' if ok else 'MISS'} {want:24} got={hits} | {q[:52]}")
for q, _ in negatives:
    hits = [h.flag_id for h in triage(q)]
    ok = len(hits) == 0
    if not ok:
        fails += 1
    print(f"{'OK ' if ok else 'FP  '} {'(none)':24} got={hits} | {q[:52]}")

print(f"\ntriage accuracy: {len(positives)+len(negatives)-fails}/{len(positives)+len(negatives)}")

# 2) force-injection: does the stroke chunk get into context for the numb query?
v2 = RagV2(mmr_lambda=0.5)
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
ctx = v2.build_context(Q, top_k=16, max_tokens=1400)
c = ctx["context"].lower()
inj_ok = ("paralysis" in c or "weakness" in c) and ("one side" in c or "cva" in c or "stroke" in c)
print(f"force-inject stroke content present: {inj_ok}")
