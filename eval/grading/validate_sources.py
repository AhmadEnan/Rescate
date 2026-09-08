"""Validate that every source / alternative_source / marker claim in a retrieval
dataset exists in the live corpus (v2 annotation model)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "eval"))
from rag_mirror.legacy_rag import LegacyRag  # noqa: E402


def main(path: str) -> int:
    rag = LegacyRag()
    ds = json.loads(Path(path).read_text())
    problems = []
    for c in ds["cases"]:
        accepted = [c["source"], *c.get("alternative_sources", [])]
        for src in accepted:
            if not any(s == src or s.startswith(src) for s in (ch["source"] for ch in rag.chunks)):
                problems.append(f"{c['id']}: source '{src}' not in corpus")
        if not any(
            c["answer_marker"].lower() in ch["text"].lower()
            and any(ch["source"] == s or ch["source"].startswith(s) for s in accepted)
            for ch in rag.chunks
        ):
            problems.append(f"{c['id']}: marker '{c['answer_marker']}' not found in any accepted source")
    if problems:
        print("PROBLEMS:")
        print("\n".join(f" - {p}" for p in problems))
        return 1
    print(f"OK: {len(ds['cases'])} cases, all source/marker claims verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else
                          str(_REPO / "eval" / "datasets" / "retrieval_suite_v2.json")))
