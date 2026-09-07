"""End-to-end eval runner: mirror-RAG + candidate model over the bilingual QA suite.

Usage:
  # with an external llama-server (recommended):
  RESCATE_EVAL_SERVER_URL=http://127.0.0.1:8080 python3 eval/harness/run_eval.py \
      --model gemma3-4b-q4km --dataset bilingual_qa_v1.json

  # with a local GGUF via llama-cpp-python:
  python3 eval/harness/run_eval.py --model mymodel --gguf /path/to/model.gguf

Writes eval/results/<model>__<dataset>.json with per-case transcripts, so
runs are comparable and reviewable. Automatic checks (must_contain /
must_not_contain) are computed here; quality rubric grading is separate
(eval/grading/rubric.md — manual or LLM-judged later).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import LegacyRag  # noqa: E402
from harness.llm_harness import get_backend, ModelSpec, save_results  # noqa: E402

DATASETS = _REPO / "eval" / "datasets"
MODELS = _REPO / "eval" / "harness" / "models.json"


def check_case(case: dict, answer: str) -> dict:
    answer_l = answer.lower()
    soft_fail, hard_fail = [], []
    for group in case.get("must_contain_any", []):
        if not any(term.lower() in answer_l for term in group):
            soft_fail.append(group)
    for group in case.get("must_not_contain_any", []):
        if any(term.lower() in answer_l for term in group):
            hard_fail.append(group)
    return {"soft_fails": soft_fail, "hard_fails": hard_fail,
            "pass": not soft_fail and not hard_fail}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="model name (key in models.json) or arbitrary label")
    ap.add_argument("--gguf", help="direct path to a GGUF file (overrides models.json)")
    ap.add_argument("--dataset", default="bilingual_qa_v1.json")
    ap.add_argument("--top-k", type=int, default=5)
    ap.add_argument("--max-tokens", type=int, default=512)
    ap.add_argument("--limit", type=int, default=0, help="only first N cases")
    ap.add_argument("--ctx", type=int, default=4096)
    args = ap.parse_args()

    rag = LegacyRag()
    dataset = json.loads((DATASETS / args.dataset).read_text())
    cases = dataset["cases"]
    if args.limit:
        cases = cases[: args.limit]

    # Resolve model backend
    spec_kwargs = {"name": args.model, "repo_id": "local", "gguf_file": ""}
    if args.gguf:
        spec_kwargs["gguf_file"] = Path(args.gguf).name
        spec = ModelSpec(**spec_kwargs)
        # trick: get_backend resolves relative to models_dir; pass absolute via env-free path
        import os
        os.environ.setdefault("RESCATE_EVAL_GGUF", args.gguf)
        backend = get_backend(spec, models_dir=str(Path(args.gguf).parent))
    else:
        models = json.loads(MODELS.read_text())
        if args.model not in models:
            print(f"Unknown model '{args.model}'. Known: {sorted(models)}")
            return 2
        m = models[args.model]
        spec = ModelSpec(name=args.model, repo_id=m["repo_id"], gguf_file=m["gguf_file"],
                         ctx_size=m.get("ctx_size", args.ctx))
        backend = get_backend(spec)

    transcripts, passed, hard_failed = [], 0, 0
    t_start = time.time()
    for case in cases:
        ctx = rag.answer_context(case["question"], top_k=args.top_k)
        prompt = ctx["prompt"]
        gen = backend.generate(prompt, max_tokens=args.max_tokens)
        checks = check_case(case, gen.text)
        passed += checks["pass"]
        hard_failed += bool(checks["hard_fails"])
        transcripts.append({
            "id": case["id"],
            "lang": case["lang"],
            "category": case.get("category"),
            "oos": case.get("oos", False),
            "question": case["question"],
            "retrieved_sources": [c["source"] for c in ctx["chunks"]],
            "answer": gen.text,
            "checks": checks,
            "timing": gen.to_dict(),
        })
        status = "PASS" if checks["pass"] else ("HARD-FAIL" if checks["hard_fails"] else "soft-fail")
        print(f"[{status:9}] {case['id']} ({gen.generated_tokens} tok, {gen.total_ms:.0f}ms)")

    report = {
        "model": args.model,
        "dataset": dataset["meta"]["name"],
        "rubric_version": dataset["meta"].get("rubric_version"),
        "top_k": args.top_k,
        "n_cases": len(cases),
        "auto_pass_rate": passed / len(cases),
        "hard_fail_rate": hard_failed / len(cases),
        "wall_time_s": round(time.time() - t_start, 1),
        "transcripts": transcripts,
    }
    out = save_results(report, f"{args.model}__{Path(args.dataset).stem}")
    print(f"\nAuto-check pass rate: {passed}/{len(cases)} ({report['auto_pass_rate']:.0%}), "
          f"hard failures: {hard_failed}")
    print(f"Saved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
