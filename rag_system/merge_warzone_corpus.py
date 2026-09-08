"""Merge warzone chunks into the master sentence corpus for rag_v2.

Produces sentences.json (v2) = legacy 312 chunks + IFRC-2025 warzone chunks,
then rebuilds vectors. Also emits a merged chunks view for reference.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
LEGACY = _REPO / "rag_system" / "chunks.json"
WAR = _REPO / "rag_system" / "chunks_warzone_ifrc2025.json"
OUT_SENT = _REPO / "eval" / "rag_mirror" / "sentences.json"

legacy = json.loads(LEGACY.read_text())
war = json.loads(WAR.read_text())

SPLIT = re.compile(r"(?<=[.!?؟])\s+|(?=\n[-•*]|\n\d+[.)]\s)")
sentences: list[dict] = []

for c in legacy:
    parts = [p.strip() for p in SPLIT.split(c["text"]) if p and len(p.strip()) > 25]
    for i, s in enumerate(parts):
        if len(s) > 600:
            subs = [x.strip() for x in s.split(";") if len(x.strip()) > 25]
            for j, sub in enumerate(subs):
                sentences.append({"id": f"{c['id']}:{i}:{j}", "chunk_id": c["id"],
                                  "source": c["source"], "pos": i, "text": sub})
        else:
            sentences.append({"id": f"{c['id']}:{i}", "chunk_id": c["id"],
                              "source": c["source"], "pos": i, "text": s})

for c in war:
    parts = [p.strip() for p in SPLIT.split(c["text"]) if p and len(p.strip()) > 25]
    for i, s in enumerate(parts):
        if len(s) > 600:
            subs = [x.strip() for x in s.split(";") if len(x.strip()) > 25]
            for j, sub in enumerate(subs):
                sentences.append({"id": f"{c['id']}:{i}:{j}", "chunk_id": c["id"],
                                  "source": c["source"], "pos": i, "text": sub})
        else:
            sentences.append({"id": f"{c['id']}:{i}", "chunk_id": c["id"],
                              "source": c["source"], "pos": i, "text": s})

OUT_SENT.write_text(json.dumps(sentences, ensure_ascii=False))
print(f"corpus: {len(legacy)} legacy + {len(war)} warzone chunks -> {len(sentences)} sentence units")
