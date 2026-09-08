import sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage
from harness.discord_bridge import build_backend, strip_think
from harness.run_eval_v2 import build_gemma_raw

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
rag = RagV2(mmr_lambda=0.5)
os.environ["RESCATE_EVAL_SERVER_URL"] = "http://127.0.0.1:8081"
backend = build_backend("gemma-4-e2b-q4km", None)

PAIRS = [
    ("en1", "someone collapsed and is not responding, what do I do?"),
    ("en2", "my friend cut his forearm with glass, it's bleeding a lot"),
    ("ar1", "ابني البلع مية ساخنة والمكوة اتحرق فيها، اعمل ايه؟"),
    ("ar2", "واحد في عربيتنا اتجرح بكسر زجاج والدم غزير، إيه الخطوات؟"),
]

for tag, q in PAIRS:
    ctx = build_context_with_triage(rag, q, top_k=16, max_tokens=1400)
    arabic = any("\u0600" <= ch <= "\u06FF" for ch in q)
    if arabic:
        user = (ctx.get("escalation_frame", "") + "\n\n" if ctx.get("escalation_frame") else "") + \
               f"المرجع الطبي:\n{ctx['context']}\n\nالسؤال: {q}"
        prompt = build_gemma_raw(ctx["context"], q, arabic=True)
        if ctx.get("escalation_frame"):
            prompt = prompt.replace("المرجع الطبي:", f"{ctx['escalation_frame']}\n\nالمرجع الطبي:", 1)
        gen = backend.generate(prompt, max_tokens=400, use_chat=False)
    else:
        user = f"MEDICAL REFERENCE:\n{ctx['context']}\n\nQUESTION: {q}"
        gen = backend.generate(user, max_tokens=400, system_prompt="You are Rescate, an offline first-aid guide for crisis settings.",
                               use_chat=True, enable_thinking=False)
    ans = strip_think(gen.text).strip()
    print(f"===== {tag}: {q}")
    print(f"[triage: {[h['flag'] for h in ctx.get('triage', [])]}]")
    print("----- RESPONSE -----")
    print(ans)
    print("===== END =====")
    sys.stdout.flush()
