"""Triage-aware context builder: wraps RagV2.build_context.

On a red-flag hit:
  1. retrieves with a flag-specific ENGLISH anchor query (clinical vocabulary)
     and force-injects its top units into the context, ahead of budget cuts
  2. prepends the escalation frame (model cannot miss it)
  3. returns augmented context with `triage` metadata
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from rag_mirror.rag_v2 import RagV2  # noqa: E402
from rag_mirror.triage import triage, escalation_frame  # noqa: E402

# English anchor queries per flag: clinical vocabulary that reliably retrieves
# the right emergency guidance from the corpus (verified via probes).
FLAG_ANCHORS: dict[str, str] = {
    "stroke": "stroke sudden weakness or numbness on one side face drooping FAST signs what to do",
    "ingestion": "poisoning swallowed pills or chemicals first aid emergency",
    "uncontrolled_bleeding": "severe life-threatening bleeding control direct pressure tourniquet",
    "airway_breathing": "choking blocked airway not breathing emergency steps",
    "unconscious": "unconscious person check breathing recovery position",
    "head_trauma": "head injury danger signs when to worry skull fracture",
    "anaphylaxis": "severe allergic reaction anaphylaxis swollen airway what to do",
    "chest_pain": "heart attack signs chest pain what to do",
    "seizure": "seizure convulsion what to do during and after recovery position",
    "severe_burn": "burn degrees classification deep third-degree burn treatment severity",
}


def build_context_with_triage(rag: RagV2, query: str, top_k: int = 16,
                              max_tokens: int = 1400, neighbors: int = 1) -> dict:
    hits = triage(query)
    arabic = any("\u0600" <= ch <= "\u06FF" for ch in query)
    ctx = rag.build_context(query, top_k=top_k, max_tokens=max_tokens, neighbors=neighbors)
    ctx["triage"] = [
        {"flag": h.flag_id, "matched": h.matched, "title": h.title} for h in hits
    ]
    if not hits:
        return ctx

    # Force-inject: retrieve with the flag's English anchor and prepend any
    # sources not already present, up to a token reserve of ~35%.
    seen_sources = set(ctx["sources"])
    reserve = int(max_tokens * 0.35)
    injected: list[str] = []
    injected_tokens = 0
    for h in hits:
        anchor = FLAG_ANCHORS.get(h.flag_id)
        if not anchor:
            continue
        actx = rag.build_context(anchor, top_k=6, max_tokens=reserve - injected_tokens,
                                 neighbors=0)
        for unit in actx["hits"]:
            if unit["source"] in seen_sources:
                continue
            cost = len(unit["text"]) / 3.7 + 12
            if injected_tokens + cost > reserve:
                break
            seen_sources.add(unit["source"])
            injected_tokens += cost
            ctx["hits"].insert(0, unit)
            ctx["context"] = f"- {unit['text']} [T{len(injected) + 1}]\n" + ctx["context"]
            injected.append(unit["source"])
    ctx["triage_injected"] = injected

    frame = escalation_frame(hits, arabic)
    ctx["escalation_frame"] = frame
    return ctx
