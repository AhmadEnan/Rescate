"""Extract conflict-relevant first-aid sections from the IFRC 2025 guidelines
into Rescate-corpus chunk format (same schema as chunks.json).

Sourced from: IFRC International First Aid, Resuscitation and Education
Guidelines 2025 (public PDF, ifrc.org) - verifiable, humanitarian,
explicitly written for conflict/disaster/fragile contexts including
prolonged care, unreliable EMS, and resource scarcity.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
SRC = _REPO / "rag_system" / "wardocs" / "ifrc_2025.txt"
OUT = _REPO / "rag_system" / "chunks_warzone_ifrc2025.json"

text = SRC.read_text()
# normalize IFRC PDF artifacts: bullet dots, soft hyphens, page footer noise
text = text.replace("\u200b", "").replace("\uf0b7", "- ").replace("\u25cf", "- ")
text = re.sub(r"International first aid, resuscitation and education guidelines 2025[^\n]*", "", text)
text = re.sub(r"CONTEXTS[^\n]*", "", text)
text = re.sub(r"\n?\\u2699[^\n]*", "", text)

# Topic sections chosen for warzone relevance (line-verified against the PDF)
SECTIONS = [
    ("warzone_ifrc2025", 2600, 2960, "Conflict settings: risks, safety, prolonged care"),
    ("warzone_ifrc2025_bleeding", 11080, 11330, "Severe bleeding control (tourniquets, packing, pressure)"),
    ("warzone_ifrc2025_chest", 11580, 11660, "Open chest and abdominal wounds (blast/gunshot)"),
    ("warzone_ifrc2025_burns", 830, 1050, "Burns and inhalation injuries"),
    ("warzone_ifrc2025_fractures", 12680, 12900, "Fractures, crush injury and immobilization"),
]


def section_text(start: int, end: int) -> str:
    lines = text.split("\n")
    chunk = "\n".join(lines[start - 1 : end])
    chunk = re.sub(r"\n{3,}", "\n\n", chunk)
    return chunk.strip()


chunks = []
for source, start, end, title in SECTIONS:
    body = section_text(start, end)
    if len(body) < 500:
        continue
    chunks.append({
        "id": f"{source}_chunk_0",
        "source": source,
        "title": title,
        "text": body,
    })

json.dump(chunks, OUT.open("w"), ensure_ascii=False, indent=1)
total = sum(len(c["text"]) for c in chunks)
print(f"wrote {len(chunks)} warzone chunks, {total} chars to {OUT.name}")
for c in chunks:
    print(f"  {c['source']:34} {len(c['text']):6} chars | {c['title']}")
