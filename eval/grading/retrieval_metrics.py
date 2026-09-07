"""Retrieval metrics + corpus validation for the Rescate eval suite (issue #14).

- validate_corpus: checks every dataset claim (source exists, answer_marker
  present in that source's chunks) so the suite is self-verifying.
- grade_retrieval: hit@k, MRR, and snippet_contains_answer over the
  retrieval_suite dataset using the LegacyRag mirror.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import LegacyRag  # noqa: E402

DATASETS = _REPO / "eval" / "datasets"


def load_jsonl_first(path: Path) -> dict:
    return json.loads(path.read_text())


def validate_corpus(rag: LegacyRag, dataset: dict) -> list[str]:
    """Return a list of problems (empty = dataset claims hold)."""
    problems = []
    sources = {c["source"] for c in rag.chunks}
    for case in dataset["cases"]:
        src = case["source"]
        marker = case["answer_marker"]
        if not any(src == s or s.startswith(src) for s in sources):
            problems.append(f"{case['id']}: source '{src}' not in corpus")
            continue
        # marker must appear in at least one chunk of a matching source
        found = any(
            marker.lower() in c["text"].lower()
            for c in rag.chunks
            if c["source"] == src or c["source"].startswith(src)
        )
        if not found:
            problems.append(f"{case['id']}: marker '{marker}' not found in source '{src}'")
    return problems


def grade_retrieval(rag: LegacyRag, dataset: dict, top_k_override: int | None = None) -> dict:
    per_case, hits, rr_sum, snippet_hits = [], 0, 0.0, 0
    for case in dataset["cases"]:
        k = top_k_override or case["k"]
        results = rag.search(case["query"], top_k=k)
        ranks = [
            i + 1
            for i, r in enumerate(results)
            if r["source"] == case["source"] or r["source"].startswith(case["source"])
        ]
        hit = bool(ranks)
        mrr = 1.0 / ranks[0] if ranks else 0.0
        # snippet check: does the snippet the app would send contain the marker?
        snippet_hit = False
        if ranks:
            top = results[ranks[0] - 1]
            snippet = rag._compact_snippet(
                re.sub(r"\s+", " ", top["text"]).strip(), case["query"]
            )
            snippet_hit = case["answer_marker"].lower() in snippet.lower()
        per_case.append({
            "id": case["id"],
            "lang": case["lang"],
            "hit@k": hit,
            "rank": ranks[0] if ranks else None,
            "mrr": round(mrr, 3),
            "snippet_contains_answer": snippet_hit,
            "top_source": results[0]["source"] if results else None,
        })
        hits += hit
        rr_sum += mrr
        snippet_hits += snippet_hit

    n = len(per_case)
    by_lang = {}
    for lang in ("en", "ar"):
        sub = [c for c in per_case if c["lang"] == lang]
        by_lang[lang] = {
            "n": len(sub),
            "hit@k": sum(c["hit@k"] for c in sub) / len(sub),
            "mrr": round(sum(c["mrr"] for c in sub) / len(sub), 3),
            "snippet_contains_answer": sum(c["snippet_contains_answer"] for c in sub) / len(sub),
        }
    return {
        "n": n,
        "hit@k": hits / n,
        "mrr": round(rr_sum / n, 3),
        "snippet_contains_answer": snippet_hits / n,
        "by_language": by_lang,
        "per_case": per_case,
    }


def main() -> int:
    rag = LegacyRag()
    dataset = load_jsonl_first(DATASETS / "retrieval_suite_v1.json")

    problems = validate_corpus(rag, dataset)
    if problems:
        print("CORPUS VALIDATION PROBLEMS (fix the dataset):")
        for p in problems:
            print(" -", p)
        return 1
    print(f"Corpus validation OK: {len(dataset['cases'])} cases, all markers verified in-corpus.")

    report = grade_retrieval(rag, dataset)
    print(json.dumps({k: v for k, v in report.items() if k != "per_case"}, ensure_ascii=False, indent=1))

    from harness.llm_harness import save_results
    out = save_results({"dataset": dataset["meta"]["name"], **report}, "retrieval_baseline")
    print(f"Saved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
