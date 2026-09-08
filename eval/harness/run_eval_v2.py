"""run_eval_v2.py — end-to-end eval with rag_v2 retrieval (sentence-level hybrid).

Same dataset + keyword checks as run_eval.py, but the model receives the
whole-sentence cited context from RagV2 instead of the legacy 180-char
snippet prompt. Gemma models keep the app's raw Gemma-4 template; other
models get the same system prompt + context via their native chat template.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import SYSTEM_PROMPT_AR, SYSTEM_PROMPT_EN  # noqa: E402
from rag_mirror.rag_v2 import RagV2, is_arabic  # noqa: E402
from harness.discord_bridge import build_backend, strip_think  # noqa: E402
from harness.run_eval import check_case  # noqa: E402
from harness.llm_harness import save_results  # noqa: E402

DATASETS = _REPO / "eval" / "datasets"


def build_user_message(context: str, question: str, arabic: bool) -> str:
    if arabic:
        return f"المرجع الطبي:\n{context}\n\nالسؤال: {question}"
    return f"MEDICAL REFERENCE:\n{context}\n\nQUESTION: {question}"


def build_gemma_raw(context: str, question: str, arabic: bool, enable_thinking: bool = False) -> str:
    system = SYSTEM_PROMPT_AR if arabic else SYSTEM_PROMPT_EN
    user = build_user_message(context, question, arabic)
    fast = (
        "السؤال واضح. أجب مباشرة باستخدام المرجع الطبي واذكر الخطوات الفورية الآمنة عند الحاجة."
        if arabic
        else "The question is clear. Answer it directly using the medical reference and give safe immediate actions when relevant."
    )
    prefix = "" if enable_thinking else f"<|channel>thought\n{fast}<channel|>\n"
    return (
        f"<|turn>system\n<|think|>\n{system}<turn|>\n"
        f"<|turn>user\n{user}<turn|>\n<|turn>model\n{prefix}"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--dataset", default="bilingual_qa_v1.json")
    ap.add_argument("--top-k", type=int, default=16)
    ap.add_argument("--ctx-tokens", type=int, default=1400)
    ap.add_argument("--max-tokens", type=int, default=350)
    ap.add_argument("--mmr-lambda", type=float, default=0.5)
    ap.add_argument("--tag", default="ragv2", help="filename tag for the results")
    args = ap.parse_args()

    rag = RagV2(mmr_lambda=args.mmr_lambda)
    if rag.vecs is None:
        raise SystemExit("vectors missing — run build_vectors first")
    dataset = json.loads((DATASETS / args.dataset).read_text())
    cases = dataset["cases"]

    backend = build_backend(args.model, None)
    is_gemma = "gemma" in args.model.lower()

    transcripts, passed, hard_failed = [], 0, 0
    t0 = time.time()
    for case in cases:
        arabic = is_arabic(case["question"])
        ctx = rag.build_context(case["question"], top_k=args.top_k, max_tokens=args.ctx_tokens)
        if is_gemma:
            prompt = build_gemma_raw(ctx["context"], case["question"], arabic)
            gen = backend.generate(prompt, max_tokens=args.max_tokens, use_chat=False)
        else:
            system = SYSTEM_PROMPT_AR if arabic else SYSTEM_PROMPT_EN
            user = build_user_message(ctx["context"], case["question"], arabic)
            gen = backend.generate(user, max_tokens=args.max_tokens, system_prompt=system,
                                   use_chat=True, enable_thinking=False)
        answer = strip_think(gen.text)
        checks = check_case(case, answer)
        passed += checks["pass"]
        hard_failed += bool(checks["hard_fails"])
        transcripts.append({
            "id": case["id"], "lang": case["lang"], "category": case.get("category"),
            "oos": case.get("oos", False), "question": case["question"],
            "retrieved_sources": ctx["sources"], "tokens_ctx": ctx["tokens_est"],
            "answer": answer, "raw_answer": gen.text,
            "checks": checks, "timing": gen.to_dict(),
        })
        st = "PASS" if checks["pass"] else ("HARD-FAIL" if checks["hard_fails"] else "soft-fail")
        print(f"[{st:9}] {case['id']} ({gen.generated_tokens} tok, {gen.total_ms:.0f}ms)", flush=True)

    report = {
        "model": args.model, "retrieval": "rag_v2", "tag": args.tag,
        "dataset": dataset["meta"]["name"], "top_k": args.top_k,
        "ctx_tokens": args.ctx_tokens, "mmr_lambda": args.mmr_lambda,
        "n_cases": len(cases),
        "auto_pass_rate": passed / len(cases),
        "hard_fail_rate": hard_failed / len(cases),
        "wall_time_s": round(time.time() - t0, 1),
        "transcripts": transcripts,
    }
    out = save_results(report, f"{args.model}__{args.tag}")
    print(f"\nAuto-check pass rate: {passed}/{len(cases)} ({report['auto_pass_rate']:.0%}), "
          f"hard failures: {hard_failed}")
    print(f"Saved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
