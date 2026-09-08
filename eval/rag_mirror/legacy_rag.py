"""Faithful Python mirror of Rescate's LegacyRag (packages/ai_inference/lib/src/legacy_rag.dart).

Ported 1:1 from the Dart implementation so eval harnesses and Discord-bot
experiments exercise the *same* retrieval + prompt-assembly pipeline the app
runs on device (issue #14). Term tables are extracted programmatically from
the Dart source (eval/rag_mirror/rag_tables.json) — never hand-copied.

Differences from the Dart original (all documented, none behavioral):
- chunks are loaded from rag_system/chunks.json (the app's bundled asset)
- the LRU search cache is omitted (harness calls are one-shot)
- Profiler counters are omitted
"""
from __future__ import annotations

import json
import re
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_TABLES = json.loads((_REPO / "eval" / "rag_mirror" / "rag_tables.json").read_text())
AR_EN_MAP_RAW: dict[str, list[str]] = _TABLES["ar_en_map"]
ACTION_TERMS: list[str] = _TABLES["action_terms"]
STOP_WORDS: set[str] = set(_TABLES["stopwords"])

_AR_CHAR = re.compile(r"[\u0600-\u06FF]")
_EN_CHAR = re.compile(r"[A-Za-z]")
# Dart: RegExp(r'[ً-ٰٟ]') — Arabic diacritics + superscript marks
_DIACRITICS = re.compile(r"[\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4]")
_NON_AR_WORD = re.compile(r"[^\u0600-\u06FFa-zA-Z0-9\s]")
_TATWEEL = "\u0640"

SYSTEM_PROMPT_EN = (
    "You are Rescate, an offline first-aid guide built for crisis and conflict "
    "settings where ambulances and hospitals may be unreachable, delayed, or "
    "dangerous to reach. Answer every clear factual or general question directly; "
    "never ask what is happening when the question is already clear. "
    "Order of thinking: 1. SAFETY FIRST: if the scene may be unsafe (fire, "
    "weapons, structural collapse, ongoing attack), state that briefly and how to "
    "reduce risk before or while treating. 2. IMMEDIATE ACTIONS: for an active "
    "emergency (severe bleeding, abnormal breathing, choking, unconsciousness, "
    "poisoning, major burn, blast injury) give short numbered actions "
    "immediately, using only what the reference and improvised materials would "
    "plausibly provide. 3. PROLONGED CARE: when advanced care may be hours away, "
    "say what to monitor and how to prevent deterioration (bleeding restart, "
    "shock, hypothermia, infection) until help is reached. 4. ESCALATION: name "
    "danger signs and advise reaching professional care when it is realistic; "
    "never assume an ambulance is available and never make reaching one a "
    "precondition of the advice. Rules: use the medical reference and never "
    "invent facts; prefer direct manual pressure for severe bleeding from a "
    "clean wound and pressure AROUND an embedded object; do not remove impaled "
    "objects; tourniquets only for life-threatening limb bleeding. Ask at most "
    "one question and only after giving immediate steps. Never reply with only "
    "a question. No greeting, disclaimer, or vague intake. Keep it concise and "
    "actionable."
)
SYSTEM_PROMPT_AR = (
    "أنت Rescate، دليل إسعافات أولية يعمل دون اتصال ومصمم لأزمات ومناطق نزاع قد "
    "تكون فيها سيارات الإسعاف والمستشفيات بعيدة المنال أو متأخرة أو خطرة الوصول. "
    "أجب مباشرة عن كل سؤال واضح، ولا تسأل عما يحدث إذا كان السؤال واضحاً بالفعل. "
    "ترتيب التفكير: 1. السلامة أولاً: إذا كان المكان قد يكون غير آمن (حريق أو "
    "أسلحة أو انهيار أو استمرار الهجوم) اذكر ذلك باختصار وكيفية تقليل الخطر قبل "
    "أو أثناء التقديم المساعدة. 2. الخطوات الفورية: عند طارئ فعلي (نزيف شديد أو "
    "اضطراب تنفس أو اختناق أو فقدان وعي أو تسمم أو حرق كبير أو إصابة انفجار) أعطِ "
    "خطوات قصيرة مرقمة فوراً باستخدام ما يوفره المرجع ومواد مرتجحة معقولة فقط. "
    "3. الرعاية الممتدة: عندما تكون الرعاية المتقدمة على بعد ساعات، اذكر ما يجب "
    "مراقبته وكيفية منع التدهور (عودة النزيف، الصدمة، انخفاض الحرارة، العدوى) "
    "حتى الوصول للمساعدة. 4. التدرج الطبي: اذكر علامات الخطر وانصح بالوصول إلى "
    "رعاية متخصصة عندما يكون ذلك واقعياً؛ لا تفترض توفر سيارة إسعاف أبداً ولا "
    "اجعل الوصول إليها شرطاً للنصيحة. القواعد: استخدم المرجع الطبي ولا تخترع "
    "معلومات؛ استخدم الضغط المباشر للنزيف الشديد من جرح نظيف والضغط حول الجسم "
    "الغريب ولا تُخرج الأجسام المثبتة؛ الرباط الضاغط فقط للنزيف المهدد للحياة "
    "في الأطراف. اسأل سؤالاً واحداً كحد أقصى بعد إعطاء الخطوات الفورية. لا ترد "
    "بسؤال فقط. بلا تحية أو إخلاء مسؤولية أو رد غامض. اجعل الإجابة قصيرة "
    "وقابلة للتنفيذ."
)

_ENGLISH_STOP_EXTRA = {
    "a", "an", "the", "and", "or", "but", "if", "then", "to", "of", "in", "on",
    "at", "by", "for", "with", "about", "into", "from", "is", "are", "was",
    "were", "be", "been", "do", "does", "did", "can", "could", "should",
    "would", "will", "shall", "may", "might", "must", "have", "has", "had",
    "i", "you", "he", "she", "it", "we", "they", "my", "your", "his", "her",
    "its", "our", "their", "what", "how", "when", "where", "which", "who",
    "why", "not",
}


class LegacyRag:
    def __init__(self, chunks_path: str | Path | None = None):
        self.chunks: list[dict] = []
        path = Path(chunks_path) if chunks_path else _REPO / "rag_system" / "chunks.json"
        raw = json.loads(path.read_text())
        for chunk in raw:
            chunk["cn"] = chunk["text"].lower()  # Dart precomputes lowercase text
            self.chunks.append(chunk)
        # Normalized keys for Arabic matching (Dart does the same per query,
        # precomputing here is a pure speedup)
        self._norm_map = {self.normalize_arabic(k): v for k, v in AR_EN_MAP_RAW.items()}

    # ---- language handling -------------------------------------------------

    @staticmethod
    def is_arabic(text: str) -> bool:
        ar = len(_AR_CHAR.findall(text))
        en = len(_EN_CHAR.findall(text))
        return ar > en

    @staticmethod
    def normalize_arabic(text: str) -> str:
        t = text.strip().lower()
        t = _DIACRITICS.sub("", t)
        t = t.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
        t = t.replace("ى", "ي").replace("ة", "ه")
        t = t.replace("ؤ", "و").replace("ئ", "ي")
        t = t.replace(_TATWEEL, "")
        t = _NON_AR_WORD.sub(" ", t)
        t = re.sub(r"\s+", " ", t).strip()
        return t

    def _english_terms_from_arabic(self, question: str) -> list[str]:
        qn = self.normalize_arabic(question)
        words = [w for w in qn.split(" ") if len(w) >= 2]
        english_terms: set[str] = set()
        for w in words:
            for key, values in self._norm_map.items():
                if w and (w in key or key in w):
                    english_terms.update(values)
        return list(english_terms)

    @staticmethod
    def _english_terms(question: str) -> list[str]:
        q = question.lower()
        q = re.sub(r"[^a-z0-9\s-]", " ", q)
        words = [w for w in q.split() if len(w) >= 3 and w not in STOP_WORDS]
        return list(dict.fromkeys(words))  # de-dup, keep order

    @staticmethod
    def _is_procedural_question(question: str) -> bool:
        q = question.lower()
        return any(
            marker in q
            for marker in (
                "how", "what should", "what do", "first aid", "steps", "treat",
                "ماذا أفعل", "كيف", "خطوات",
            )
        )

    # ---- scoring ------------------------------------------------------------

    @staticmethod
    def _count_occurrences(text: str, term: str) -> int:
        if not term:
            return 0
        return text.count(term)

    def _score_chunk(
        self, text: str, terms: list[str], raw_words: list[str], *, procedural: bool
    ) -> float:
        normalized = re.sub(r"\s+", " ", text).lower()
        candidates: list[int] = []
        for term in set(terms) | set(ACTION_TERMS):
            start = 0
            while True:
                idx = normalized.find(term, start)
                if idx < 0:
                    break
                candidates.append(idx)
                start = idx + len(term)
        if not candidates:
            return 0.0

        window_size = 360
        raw_set = set(raw_words)
        best = 0.0
        for candidate in candidates:
            window_start = max(0, candidate - 90)
            end = min(len(normalized), window_start + window_size)
            window = normalized[window_start:end]
            score = 0.0
            has_query_term = False
            for term in terms:
                occurrences = self._count_occurrences(window, term)
                if occurrences == 0:
                    continue
                has_query_term = True
                weight = 4.0 if term in raw_set else 2.0
                score += weight * min(max(occurrences, 1), 3)
            if not has_query_term:
                continue
            if procedural:
                for action in ACTION_TERMS:
                    if action in window:
                        score += 6.0
            if "available at:" in window or "http" in window:
                score -= 20.0
            if "references:" in window or ("sources:" in window and not procedural):
                score -= 10.0
            best = max(best, score)
        return best

    def _compact_snippet(self, text: str, question: str) -> str:
        max_length = 180
        if len(text) <= max_length:
            return text
        query_terms = self._english_terms(question)
        terms = set(query_terms) | set(ACTION_TERMS)
        normalized = text.lower()
        best_start, best_score = 0, -1.0
        for term in terms:
            search_start = 0
            while True:
                idx = normalized.find(term.lower(), search_start)
                if idx < 0:
                    break
                start = min(max(0, idx - 35), max(0, len(text) - max_length))
                window = normalized[start : start + max_length]
                score = 0.0
                for qt in query_terms:
                    score += 3.0 * min(self._count_occurrences(window, qt), 3)
                if self._is_procedural_question(question):
                    for action in ACTION_TERMS:
                        if action in window:
                            score += 5.0
                if score > best_score:
                    best_score, best_start = score, start
                search_start = idx + len(term)
        return text[best_start : best_start + max_length] + "..."

    # ---- public API ---------------------------------------------------------

    def search(self, question: str, top_k: int = 5) -> list[dict]:
        if not self.chunks:
            return []
        is_ar = self.is_arabic(question)
        raw_words = [
            w
            for w in (self.normalize_arabic(question) if is_ar else question.lower()).split(" ")
            if len(w) >= 3
        ]
        terms_to_search = (
            self._english_terms_from_arabic(question) if is_ar else self._english_terms(question)
        )
        all_terms = list(dict.fromkeys([*terms_to_search, *raw_words]))
        procedural = self._is_procedural_question(question)

        scored = []
        for chunk in self.chunks:
            text = chunk["text"]
            score = self._score_chunk(text, all_terms, raw_words, procedural=procedural)
            if score > 0:
                scored.append(
                    {"source": chunk["source"], "text": text, "score": float(score)}
                )
        scored.sort(key=lambda r: r["score"], reverse=True)
        return scored[:top_k]

    def build_prompt(
        self,
        question: str,
        chunks: list[dict],
        tool_declarations: str | None = None,
        enable_thinking: bool = False,
    ) -> str:
        """Mirrors LegacyRag.buildPrompt including the Gemma 4 turn template."""
        arabic = self.is_arabic(question)
        system_prompt = SYSTEM_PROMPT_AR if arabic else SYSTEM_PROMPT_EN
        if tool_declarations:
            system_prompt = f"{system_prompt}\n\n{tool_declarations}"

        if not chunks:
            context = "NO_RELEVANT_CONTEXT"
        else:
            compact = []
            for i, c in enumerate(chunks):
                text = re.sub(r"\s+", " ", c["text"]).strip()
                compact.append(f"[{i + 1}]\n{self._compact_snippet(text, question)}")
            context = "\n\n---\n\n".join(compact)

        user_msg = (
            f"المرجع الطبي:\n{context}\n\nالسؤال: {question}"
            if arabic
            else f"MEDICAL REFERENCE:\n{context}\n\nQUESTION: {question}"
        )

        fast_thought = (
            "السؤال واضح. أجب مباشرة باستخدام المرجع الطبي واذكر الخطوات الفورية الآمنة عند الحاجة."
            if arabic
            else "The question is clear. Answer it directly using the medical reference and give safe immediate actions when relevant."
        )
        model_prefix = "" if enable_thinking else f"<|channel>thought\n{fast_thought}<channel|>\n"
        return (
            f"<|turn>system\n<|think|>\n{system_prompt}<turn|>\n"
            f"<|turn>user\n{user_msg}<turn|>\n"
            f"<|turn>model\n{model_prefix}"
        )

    def answer_context(self, question: str, top_k: int = 5) -> dict:
        """One-shot convenience: retrieve + build the exact model prompt."""
        chunks = self.search(question, top_k=top_k)
        return {
            "chunks": chunks,
            "prompt": self.build_prompt(question, chunks),
            "language": "ar" if self.is_arabic(question) else "en",
        }
