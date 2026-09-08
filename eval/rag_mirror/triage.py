"""Red-flag symptom triage layer (Path B from the night-build discussion).

Pattern-matches a multilingual lexicon of emergency red-flag phrases against
every user query BEFORE retrieval. On a hit:
  1. force-injects the matching emergency chunk (bypassing retrieval score)
  2. prepends an escalation frame to the context the model cannot ignore
  3. records the flag for audit/eval

Design goals: <1ms, no model call, auditable, catches ANY phrasing of a
known red flag even when embeddings miss (colloquial Arabic included).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class TriageHit:
    flag_id: str
    matched: list[str] = field(default_factory=list)
    title: str = ""


# Lexicon: flag_id -> (en/ar/colloquial surface forms). All lowercase.
# Matching is substring on a normalized query (Arabic normalization applied).
RED_FLAGS: dict[str, tuple[str, ...]] = {
    "stroke": (
        "numb", "can't feel", "cant feel", "no feeling in", "won't move", "wont move",
        "not moving", "doesn't move", "doesnt move", "paralyzed", "limp",
        "face drooping", "slurred", "one side weak", "weak on one side", "one side",
        "منمل", "تنميل", "خدر", "مش حاسس", "مص قاسس", "شلل", "ضعف في", "تلثث", "ارتباك مفاجئ",
        "مش معايا", "مش بيتحرك", "رجلي", "رجله", "ايدي",
    ),
    "ingestion": (
        "swallowed", "drank", "ate the", "ate some", "chewed", "pill", "pills",
        "bleach", "detergent", "medicine bottle",
        "ابتلع", "بلع", "شرب", "حبوب", "دوا", "دواء", "كلور",
    ),
    "uncontrolled_bleeding": (
        "soaking through", "blood everywhere", "won't stop bleeding", "wont stop bleeding",
        "spurting", "blood keeps coming",
        "نزيف", "دم كتير", "الدم غزير", "ما بيوقفش", "مش بيقف",
    ),
    "airway_breathing": (
        "can't breathe", "cant breathe", "not breathing", "choking", "gasping",
        "wheezing badly", "throat closing",
        "مش يتنفس", "لا يتنفس", "يخنق", "اختناق", "مش قادر يتنفس", "ضيق تنفس",
    ),
    "unconscious": (
        "unconscious", "not waking up", "passed out", "collapsed", "no response",
        "فاقد الوعي", "فاقد وعي", "ما صحيش", "غيبوبة", "سقط مغشي عليه",
    ),
    "head_trauma": (
        "fell down the stairs", "hit his head", "hit her head", "head injury",
        "قعت", "سقط", "ضرب في راسه", "إصابة في الرأس", "اصابة في الراس",
    ),
    "anaphylaxis": (
        "swollen face", "swollen tongue", "hives all over", "throat swelling",
        "stung by", "allergic reaction", "anaphylaxis",
        "تورم الوجه", "تورم اللسان", "حساسية شديده", "تحسس شديد", "تضعف التنفس من اللسعه",
    ),
    "chest_pain": (
        "chest pain", "chest pressure", "pain in my chest", "crushing chest",
        "الم في الصدر", "ألم في الصدر", "ضغط في الصدر", "الصدر بتقيل",
    ),
    "seizure": (
        "seizure", "convulsion", "shaking uncontrollably", "twitching and not respond",
        "تشنج", "صرع", "اختلاج",
    ),
    "severe_burn": (
        "burned", "burnt", "burn on", "scalded",
        "حرق", "احترق", "اتحرق",
    ),
}

# Symptoms whose severity class the answer must state explicitly.
SEVERITY_HINTS: dict[str, str] = {
    "stroke": "possible STROKE (FAST: face drooping, arm weakness, speech difficulty, time-critical)",
    "ingestion": "suspected POISONING - time-critical even if the person seems fine",
    "uncontrolled_bleeding": "severe bleeding - pressure cannot be released",
    "airway_breathing": "airway/breathing emergency",
    "unconscious": "unresponsive person - check breathing and pulse, recovery position if breathing",
    "head_trauma": "possible head/spinal injury - minimize movement",
    "anaphylaxis": "possible ANAPHYLAXIS - airway swelling can be fatal within minutes",
    "chest_pain": "possible cardiac event",
    "seizure": "active or recent seizure",
    "severe_burn": "burn - depth and extent determine severity; painlessness suggests DEEP burn",
}

_AR_DIAC = re.compile(r"[\u064B-\u0652\u0670]")  # tashkeel
_AR_TATWEEL = "\u0640"


def normalize_ar(text: str) -> str:
    """Light Arabic normalization: strip diacritics/tatweel, unify alef/yaa/ta-marbuta."""
    t = _AR_DIAC.sub("", text)
    t = t.replace(_AR_TATWEEL, "")
    t = re.sub("[أإآٱ]", "ا", t)
    t = t.replace("ى", "ي").replace("ة", "ه")
    return t


def triage(query: str) -> list[TriageHit]:
    """Return every red flag whose surface form appears in the query."""
    q = query.lower()
    qn = normalize_ar(q)
    hits: list[TriageHit] = []
    for flag_id, forms in RED_FLAGS.items():
        matched = []
        for form in forms:
            if form in q or normalize_ar(form) in qn:
                matched.append(form)
        if matched:
            hits.append(TriageHit(flag_id=flag_id, matched=matched, title=SEVERITY_HINTS.get(flag_id, "")))
    return hits


def escalation_frame(hits: list[TriageHit], arabic: bool) -> str:
    """Mandatory reasoning frame prepended to the model's user message."""
    if not hits:
        return ""
    titles = "; ".join(h.title for h in hits if h.title)
    if arabic:
        return (
            f"⚠️ تنبيه تريج: يوجد مؤشرات على حالة طارئة ({titles}). "
            "أجب وفق إطار الطوارئ: عالجها كحالة خطيرة حتى يثبت العكس، اذكر لماذا "
            "هذه الأعراض خطيرة تحديداً، وأعطِ خطوات فورية + متى تطلب رعاية عاجلة."
        )
    return (
        f"⚠️ TRIAGE ALERT: the query contains red-flag signs ({titles}). "
        "Answer using the emergency frame: treat as serious until proven otherwise, "
        "explain WHY these specific symptoms are dangerous, give immediate actions "
        "and when to seek urgent care."
    )
