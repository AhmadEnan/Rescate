import sys, os, json
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.rag_v2 import RagV2
from rag_mirror.triage_context import build_context_with_triage
from rag_mirror.legacy_rag import SYSTEM_PROMPT_AR
from harness.discord_bridge import build_backend, strip_think
from harness.run_eval_v2 import build_gemma_raw

Q = "ابني الرضيع محتاج ياكل بس مفيش لبن ممكن ااكله ايه"

rag = RagV2(mmr_lambda=0.5)
ctx = build_context_with_triage(rag, Q, top_k=16, max_tokens=1400)

os.environ["RESCATE_EVAL_SERVER_URL"] = "http://127.0.0.1:8081"
backend = build_backend("gemma-4-e2b-q4km", None)
prompt = build_gemma_raw(ctx["context"], Q, arabic=True)
gen = backend.generate(prompt, max_tokens=450, use_chat=False)
print(strip_think(gen.text).strip())
