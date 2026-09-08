"""Compare rag_v2 (sentence-level hybrid) against the LegacyRag mirror
on the same retrieval suite. Reports hit@k, MRR, snippet-context coverage,
per language, plus per-case misses for diagnosis."""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))

from rag_mirror.legacy_rag import LegacyRag  # noqa: E402
from rag_mirror.rag_v2 import RagV2  # noqa: E402


def source_matches(src: str, target: str) -> bool:
    return src == target or src.startswith(target)


def eval_legacy(rag: LegacyRag, cases: list[dict]) -> list[dict]:
    rows = []
    for c in cases:
        res = rag.search(c["query"], top_k=c["k"])
        accepted = [c["source"], *c.get("alternative_sources", [])]
        ranks = [i + 1 for i, r in enumerate(res)
                 if any(source_matches(r["source"], s) for s in accepted)]
        hit = bool(ranks)
        snippet_hit = False
        if ranks:
            top = res[ranks[0] - 1]
            snip = rag._compact_snippet(re.sub(r"\s+", " ", top["text"]).strip(), c["query"])
            snippet_hit = c["answer_marker"].lower() in snip.lower()
        rows.append({"id": c["id"], "lang": c["lang"], "hit": hit,
                     "rank": ranks[0] if ranks else None,
                     "mrr": 1.0 / ranks[0] if ranks else 0.0,
                     "answer_in_context": snippet_hit})
    return rows


def eval_v2(rag: RagV2, cases: list[dict]) -> list[dict]:
    rows = []
    for c in cases:
        ctx = rag.build_context(c["query"], top_k=c["k"] * 3, max_tokens=1000)
        accepted = [c["source"], *c.get("alternative_sources", [])]
        ranks = [i + 1 for i, h in enumerate(ctx["hits"])
                 if any(source_matches(h["source"], s) for s in accepted)]
        hit = bool(ranks)
        marker = c["answer_marker"].lower()
        in_ctx = marker in ctx["context"].lower()
        rows.append({"id": c["id"], "lang": c["lang"], "hit": hit,
                     "rank": ranks[0] if ranks else None,
                     "mrr": 1.0 / ranks[0] if ranks else 0.0,
                     "answer_in_context": in_ctx})
    return rows


def summarize(name: str, rows: list[dict]) -> dict:
    n = len(rows)
    out = {"system": name, "n": n,
           "hit@k": sum(r["hit"] for r in rows) / n,
           "mrr": round(sum(r["mrr"] for r in rows) / n, 3),
           "answer_in_context": sum(r["answer_in_context"] for r in rows) / n}
    for lang in ("en", "ar"):
        sub = [r for r in rows if r["lang"] == lang]
        out[f"{lang}_hit"] = sum(r["hit"] for r in sub) / len(sub)
        out[f"{lang}_answer_in_context"] = sum(r["answer_in_context"] for r in sub) / len(sub)
    return out


def main() -> int:
    import sys as _sys
    ds_path = _sys.argv[1] if len(_sys.argv) > 1 else str(_REPO / "eval" / "datasets" / "retrieval_suite_v2.json")
    cases = json.loads(Path(ds_path).read_text())["cases"]

    legacy = LegacyRag()
    t0 = time.time()
    rows_legacy = eval_legacy(legacy, cases)
    t_legacy = time.time() - t0

    v2 = RagV2()
    assert v2.vecs is not None, "run build_vectors first"
    t0 = time.time()
    rows_v2 = eval_v2(v2, cases)
    t_v2 = time.time() - t0

    s1 = summarize("legacy (chunk+termmap+180char)", rows_legacy)
    s2 = summarize("v2 (sentence+embed+bm25+rrf)", rows_v2)
    print(f"{'system':34} {'hit@k':>6} {'mrr':>6} {'ans-in-ctx':>10} {'en-hit':>7} {'ar-hit':>7} {'en-ctx':>7} {'ar-ctx':>7}")
    for s in (s1, s2):
        print(f"{s['system']:34} {s['hit@k']:>6.0%} {s['mrr']:>6.2f} {s['answer_in_context']:>10.0%} "
              f"{s['en_hit']:>7.0%} {s['ar_hit']:>7.0%} {s['en_answer_in_context']:>7.0%} {s['ar_answer_in_context']:>7.0%}")
    print(f"\nlatency: legacy {t_legacy:.1f}s total ({t_legacy/len(cases)*1000:.0f}ms/q), "
          f"v2 {t_v2:.1f}s total ({t_v2/len(cases)*1000:.0f}ms/q incl. embedding)")

    print("\n--- v2 misses (diagnosis) ---")
    for c, r in zip(cases, rows_v2):
        if not r["hit"]:
            print(f"  {c['id']:18} wanted: {c['source'][:38]}")

    out = _REPO / "eval" / "results" / "retrieval_v2_vs_v1.json"
    out.write_text(json.dumps({
        "legacy": s1, "v2": s2, "rows_legacy": rows_legacy, "rows_v2": rows_v2,
        "latency_legacy_ms_per_q": t_legacy / len(cases) * 1000,
        "latency_v2_ms_per_q": t_v2 / len(cases) * 1000,
    }, ensure_ascii=False, indent=1))
    print(f"saved {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
