import json, sys, os
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage
from rag_mirror.legacy_rag import SYSTEM_PROMPT_AR
from harness.discord_bridge import build_backend, strip_think
from harness.run_eval_v2 import build_gemma_raw

os.environ.setdefault("RESCATE_EVAL_SERVER_URL", "http://127.0.0.1:8084")
Q = "انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها"
rag = RagV2(mmr_lambda=0.5)
ctx = build_context_with_triage(rag, Q, top_k=16, max_tokens=1600, neighbors=1)
user = (ctx["escalation_frame"] + "\n\n" +
        f"المرجع الطبي:\n{ctx['context']}\n\nالسؤال: {Q}")
os.environ["RESCATE_EVAL_SERVER_URL"] = "http://127.0.0.1:8081"
backend = build_backend("gemma-4-e2b-q4km", None)
prompt = build_gemma_raw(ctx["context"], Q, arabic=True, enable_thinking=False)
# prepend the escalation frame INSIDE the user turn via raw template
prompt = prompt.replace("المرجع الطبي:", f"{ctx['escalation_frame']}\n\nالمرجع الطبي:", 1)
gen = backend.generate(prompt, max_tokens=450, use_chat=False)
print(strip_think(gen.text).strip())
