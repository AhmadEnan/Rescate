"""
rag_server_fixed.py
Fixes:
- Separate health checks: RAG status independent of llama status
- Faster response: reduced default tokens + lower timeout
- Better CORS + OPTIONS handling
- Startup diagnostics
- Graceful llama.cpp connection errors (won't crash server)
"""

import json, os, re, sys, unicodedata, urllib.request, urllib.error

try:
    from flask import Flask, request, jsonify, Response
except ImportError:
    print("Run: python -m pip install flask")
    sys.exit(1)

LLAMA_URL   = "http://localhost:8080/completion"
LLAMA_HEALTH = "http://localhost:8080/health"
INDEX_DIR   = "search_index"
CHUNKS_FILE = "chunks.json"
PORT        = 8081

# ── Speed tip: reduce n_predict default, Gemma 4 is slow on CPU ──────────────
DEFAULT_MAX_TOKENS  = 300   # was 400 in HTML, keep it short for speed
DEFAULT_TEMPERATURE = 0.05
DEFAULT_TOP_K       = 4     # fewer chunks = shorter prompt = faster
SYSTEM_PROMPT_EN = """You are a medical reference assistant.

Your goal is to provide COMPLETE, DETAILED, and WELL-STRUCTURED explanations based ONLY on the provided medical reference.

Hard rules:
1) Use ONLY the MEDICAL REFERENCE supplied in the user message.
2) If the reference does not contain enough information, say exactly:
   This information is not available in the provided documents.
3) Do not add medical facts that are not explicitly supported by the reference.
4) YOU MUST REPLY IN ENGLISH ONLY.
5) Do not mention the reference, documents, prompt, or context.
6) Do not output chain-of-thought. Keep reasoning hidden.

Response requirements (VERY IMPORTANT):
- Your answer MUST be detailed, not concise.
- Expand fully on all relevant points found in the reference.
- Do NOT summarize unless explicitly asked.
- Explain concepts clearly as if teaching a medical student.

7) Important Notes  
- Include any critical details, warnings, or clarifications from the reference.


"""

SYSTEM_PROMPT_AR = """أنت مساعد مرجعي طبي.

هدفك هو تقديم شرح كامل ومفصل ومنظم اعتماداً فقط على المرجع الطبي المقدم.

القواعد الصارمة:
١) استخدم فقط المرجع الطبي الموجود في رسالة المستخدم.
٢) إذا لم يحتوي المرجع على معلومات كافية، قل بالضبط:
   هذه المعلومات غير متوفرة في الوثائق المتاحة.
٣) لا تضف أي معلومات طبية غير موجودة صراحةً في المرجع.
٤) يجب أن تكون الإجابة باللغة العربية فقط.
٥) لا تذكر المرجع أو المستندات أو الموجه أو السياق.
٦) لا تُظهر طريقة التفكير الداخلية.

متطلبات الإجابة (مهم جداً):
- يجب أن تكون الإجابة مفصلة وليست مختصرة.
- قم بشرح جميع النقاط الموجودة في المرجع بشكل كامل.
- لا تختصر إلا إذا طُلب منك ذلك.
- اشرح كأنك تشرح لطالب طب.

"""
app = Flask(__name__)
raw_chunks = []
ix = None

# ── Arabic ↔ English keyword map (kept from original) ────────────────────────
AR_EN_MAP = {
    "حرق": ["burn", "burns", "burning"],
    "حروق": ["burn", "burns", "burning"],
    "لسعة": ["burn", "skin injury"],
    "حار": ["burn", "heat injury", "hot"],
    "نار": ["burn", "flame burn", "fire"],
    "لهب": ["flame burn", "burn", "fire"],
    "سخن": ["heat", "hot", "burn"],
    "ساخن": ["heat", "hot", "burn"],
    "حرارة": ["fever", "temperature", "heat"],
    "سخونية": ["fever", "temperature", "heat"],
    "تبريد": ["cool", "cooling", "burn care"],
    "برد": ["cold", "hypothermia"],
    "ثلج": ["ice", "cold", "burn cooling"],
    "انفجار": ["explosion", "blast", "blast injury", "trauma"],
    "تفجير": ["explosion", "blast"],
    "دخان": ["smoke", "inhalation", "airway"],
    "استنشاق": ["inhalation", "airway", "breathing"],
    "اختناق": ["airway", "breathing", "choking"],
    "تنفس": ["breathing", "respiratory", "airway", "inhalation"],
    "هواء": ["airway", "breathing", "oxygen", "inhalation"],
    "أكسجين": ["oxygen", "airway", "breathing"],
    "اكسجين": ["oxygen", "airway", "breathing"],
    "فوسفور": ["phosphorus", "white phosphorus", "chemical burn"],
    "فسفور": ["phosphorus", "white phosphorus", "chemical burn"],
    "ابيض": ["white phosphorus", "chemical burn"],
    "أبيض": ["white phosphorus", "chemical burn"],
    "كيميائي": ["chemical burn", "chemical"],
    "مواد": ["chemical", "exposure", "burn"],
    "حمض": ["acid", "chemical burn"],
    "قلوي": ["alkali", "chemical burn"],
    "كهربائي": ["electrical burn", "electrical"],
    "كهربا": ["electrical", "electrical burn", "shock"],
    "صعق": ["electrical burn", "electrical", "shock"],
    "تيار": ["electrical", "current", "shock"],
    "مياه": ["water", "fluid", "hydration"],
    "ماء": ["water", "fluid", "hydration"],
    "درجة": ["degree", "grade", "classification"],
    "درجه": ["degree", "grade", "classification"],
    "أولى": ["first degree", "superficial burn"],
    "اولى": ["first degree", "superficial burn"],
    "ثانية": ["second degree", "partial thickness burn"],
    "ثانيه": ["second degree", "partial thickness burn"],
    "ثالثة": ["third degree", "full thickness burn"],
    "ثالثه": ["third degree", "full thickness burn"],
    "سطحي": ["superficial burn", "first degree"],
    "سطحية": ["superficial burn", "superficial"],
    "جزئي": ["partial thickness burn", "second degree"],
    "عميق": ["deep partial thickness", "deep burn"],
    "كامل": ["full thickness", "third degree"],
    "فقاعات": ["blisters", "second degree burn"],
    "فقاعة": ["blister", "second degree burn"],
    "بثور": ["blisters", "burn"],
    "جلد": ["skin", "dermis", "epidermis"],
    "ابيضت": ["white", "full thickness burn"],
    "اسود": ["charred", "black", "full thickness burn"],
    "متفحم": ["charred", "full thickness burn"],
    "جرح": ["wound", "injury", "laceration"],
    "جروح": ["wound", "injury", "laceration"],
    "قطع": ["cut", "laceration", "wound"],
    "طعن": ["penetrating wound", "stab wound", "injury"],
    "نزيف": ["bleeding", "hemorrhage"],
    "ينزف": ["bleeding", "hemorrhage"],
    "دم": ["blood", "bleeding", "hemorrhage"],
    "شظية": ["shrapnel", "fragment", "blast injury"],
    "شظايا": ["shrapnel", "fragment", "blast injury"],
    "رصاص": ["bullet", "gunshot", "gunshot wound"],
    "طلقة": ["gunshot", "bullet wound"],
    "إصابة": ["injury", "trauma", "wound"],
    "اصابة": ["injury", "trauma", "wound"],
    "صدمة": ["shock", "trauma", "injury"],
    "صدمه": ["shock", "trauma", "injury"],
    "رض": ["trauma", "injury", "blunt trauma"],
    "كدمة": ["bruise", "contusion", "injury"],
    "كسر": ["fracture", "broken bone"],
    "كسور": ["fracture", "broken bone"],
    "عظم": ["bone", "fracture", "orthopedic"],
    "عظام": ["bone", "fracture", "orthopedic"],
    "خلع": ["dislocation", "joint injury"],
    "التواء": ["sprain", "strain"],
    "بتر": ["amputation", "traumatic amputation"],
    "سحق": ["crush injury", "collapse", "trauma"],
    "انهيار": ["collapse", "building collapse", "crush injury"],
    "تورم": ["swelling", "edema", "injury"],
    "ورم": ["swelling", "edema"],
    "هوائي": ["airway", "breathing"],
    "تنفسه": ["breathing", "respiratory"],
    "يتنفس": ["breathing", "respiratory"],
    "نفس": ["breathing", "respiratory"],
    "لهاث": ["shortness of breath", "respiratory distress"],
    "نهجان": ["shortness of breath", "breathing difficulty"],
    "يزرق": ["blue lips", "cyanosis", "low oxygen"],
    "ازرق": ["cyanosis", "low oxygen"],
    "ازرقاق": ["cyanosis", "low oxygen"],
    "شرق": ["choking", "airway obstruction"],
    "بلع": ["swallowing", "airway", "choking"],
    "انسداد": ["obstruction", "blocked airway"],
    "انعاش": ["CPR", "resuscitation"],
    "إنعاش": ["CPR", "resuscitation"],
    "قلب": ["heart", "cardiac", "pulse"],
    "نبض": ["pulse", "heartbeat", "cardiac"],
    "تنفس صناعي": ["rescue breaths", "resuscitation", "CPR"],
    "ضغطات": ["chest compressions", "CPR"],
    "صدر": ["chest", "thoracic", "lung"],
    "رئة": ["lung", "breathing", "respiratory"],
    "رئه": ["lung", "breathing", "respiratory"],
    "ولادة": ["childbirth", "delivery", "labor"],
    "ولاده": ["childbirth", "delivery", "labor"],
    "طلق": ["labor", "delivery", "contractions"],
    "حامل": ["pregnancy", "pregnant"],
    "حمل": ["pregnancy", "pregnant"],
    "نفاس": ["postpartum", "after birth"],
    "بعد الولادة": ["postpartum", "after delivery"],
    "بعد الولاده": ["postpartum", "after delivery"],
    "نزيف بعد الولادة": ["postpartum hemorrhage", "bleeding after birth"],
    "مشيمة": ["placenta", "retained placenta"],
    "مشيمه": ["placenta", "retained placenta"],
    "رحم": ["uterus", "uterine"],
    "تشنج": ["seizure", "eclampsia", "convulsion"],
    "تشنجات": ["seizure", "eclampsia", "convulsion"],
    "صرع": ["seizure", "convulsion"],
    "مولود": ["newborn", "baby", "neonate"],
    "مواليد": ["newborn", "neonate"],
    "رضيع": ["infant", "baby", "newborn"],
    "طفل": ["child", "baby", "infant"],
    "بيبي": ["baby", "newborn", "infant"],
    "مبتسر": ["premature baby", "preterm", "newborn"],
    "خديج": ["premature baby", "preterm", "newborn"],
    "لا يرضع": ["not feeding", "newborn emergency", "sepsis"],
    "يرضع": ["feeding", "breastfeeding", "newborn"],
    "رضاعة": ["breastfeeding", "feeding"],
    "يبكي": ["crying", "newborn assessment"],
    "لا يبكي": ["newborn not breathing", "resuscitation", "newborn emergency"],
    "لا يتنفس": ["not breathing", "resuscitation", "airway"],
    "بردان": ["hypothermia", "too cold", "newborn hypothermia"],
    "بارد": ["cold", "hypothermia"],
    "حمى": ["fever", "infection", "temperature"],
    "حرارته": ["fever", "temperature", "hot"],
    "السره": ["umbilical cord", "cord infection", "newborn"],
    "سرة": ["umbilical cord", "cord infection", "newborn"],
    "سره": ["umbilical cord", "cord infection", "newborn"],
    "صديد": ["pus", "infection", "umbilical infection"],
    "يرقان": ["jaundice", "newborn infection"],
    "صفار": ["jaundice", "newborn"],
    "عدوى": ["infection", "sepsis"],
    "التهاب": ["infection", "inflammation"],
    "تلوث": ["contamination", "infection"],
    "قيح": ["pus", "infection"],
    "قشعريرة": ["chills", "infection", "fever"],
    "خمول": ["lethargy", "weakness", "newborn infection"],
    "ضعف": ["weakness", "fatigue"],
    "يرتجف": ["shivering", "cold", "fever"],
    "تعفن": ["sepsis", "infection"],
    "تسمم": ["sepsis", "toxic", "poisoning"],
    "جلطة": ["stroke", "clot", "thrombosis", "embolism"],
    "سكتة": ["stroke", "brain emergency"],
    "سكتة دماغية": ["stroke", "cerebral"],
    "دماغ": ["brain", "cerebral", "stroke"],
    "دماغية": ["brain", "cerebral", "stroke"],
    "رأس": ["head", "brain", "head injury"],
    "راس": ["head", "brain", "head injury"],
    "دوخة": ["dizziness", "vertigo", "fainting"],
    "دوار": ["dizziness", "vertigo"],
    "إغماء": ["fainting", "unconscious", "collapse"],
    "اغماء": ["fainting", "unconscious", "collapse"],
    "مغمى": ["unconscious", "collapse"],
    "مغمي": ["unconscious", "collapse"],
    "تشوش": ["confusion", "altered mental status"],
    "ارتباك": ["confusion", "altered mental status"],
    "شلل": ["paralysis", "stroke", "neurologic deficit"],
    "خدر": ["numbness", "neurologic deficit"],
    "ألم": ["pain"],
    "الم": ["pain"],
    "وجع": ["pain"],
    "حارق": ["burning pain", "burn"],
    "بطن": ["abdomen", "abdominal", "stomach"],
    "معدة": ["stomach", "abdomen"],
    "ظهر": ["back", "spine"],
    "رقبة": ["neck", "airway", "trauma"],
    "عين": ["eye", "ocular", "vision"],
    "اذن": ["ear", "hearing"],
    "أذن": ["ear", "hearing"],
    "يد": ["hand", "upper limb"],
    "رجل": ["leg", "lower limb"],
    "ساق": ["leg", "limb", "extremity"],
    "ذراع": ["arm", "upper limb", "extremity"],
    "علاج": ["treatment", "therapy", "management"],
    "تدبير": ["management", "treatment"],
    "تصرف": ["what to do", "management", "first aid"],
    "اعمل": ["what to do", "management", "first aid"],
    "أسعف": ["first aid", "emergency treatment"],
    "اسعف": ["first aid", "emergency treatment"],
    "إسعاف": ["first aid", "emergency", "treatment"],
    "اسعاف": ["first aid", "emergency", "treatment"],
    "ماذا": ["what", "management"],
    "شلون": ["what to do", "management"],
    "ازاي": ["what to do", "management"],
    "كيف": ["how", "management"],
    "سوائل": ["fluids", "resuscitation", "hydration"],
    "محلول": ["IV fluid", "resuscitation", "lactated ringer"],
    "رينجر": ["lactated ringer", "ringer lactate", "fluid resuscitation"],
    "تعويض": ["resuscitation", "fluids"],
    "جفاف": ["dehydration", "fluids", "hydration"],
    "ترطيب": ["hydration", "fluids"],
    "بول": ["urine output", "kidney", "resuscitation"],
    "تبول": ["urine output", "kidney"],
    "ابني": ["my baby", "child", "newborn", "infant"],
    "بنتي": ["my baby", "child", "infant"],
    "عيلي": ["my child", "baby", "infant"],
    "طفلي": ["my child", "baby", "infant"],
    "مراتي": ["wife", "mother", "postpartum"],
    "مرتي": ["wife", "mother", "postpartum"],
    "امي": ["mother", "adult patient"],
    "أمي": ["mother", "adult patient"],
}


# ── Utility ───────────────────────────────────────────────────────────────────

def load():
    global raw_chunks, ix
    if os.path.exists(CHUNKS_FILE):
        with open(CHUNKS_FILE, "r", encoding="utf-8") as f:
            raw_chunks = json.load(f)
        print(f"✅ {len(raw_chunks)} chunks loaded from {CHUNKS_FILE}")
    else:
        print(f"⚠  {CHUNKS_FILE} not found — RAG will return no chunks")
    try:
        from whoosh import index as wi
        if os.path.exists(INDEX_DIR):
            ix = wi.open_dir(INDEX_DIR)
            print("✅ Whoosh index opened")
        else:
            print(f"⚠  {INDEX_DIR}/ not found — keyword search disabled")
    except ImportError:
        print("⚠  whoosh not installed — pip install whoosh")


def is_arabic(text: str) -> bool:
    ar = len(re.findall(r'[\u0600-\u06FF]', text))
    en = len(re.findall(r'[A-Za-z]', text))
    return ar > en


def normalize_arabic(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r'[\u064b-\u065f\u0670]', '', text)
    text = text.replace('أ','ا').replace('إ','ا').replace('آ','ا')
    text = text.replace('ى','ي').replace('ة','ه')
    text = text.replace('ؤ','و').replace('ئ','ي')
    text = text.replace('ـ', '')
    text = re.sub(r'[^\u0600-\u06FFa-zA-Z0-9\s]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def arabic_keywords(question: str):
    qn = normalize_arabic(question)
    words = [w for w in qn.split() if len(w) >= 2]
    english_terms = []
    normalized_map = {normalize_arabic(k): v for k, v in AR_EN_MAP.items()}
    for w in words:
        for ar_key, vals in normalized_map.items():
            if ar_key in w or w in ar_key:
                english_terms.extend(vals)
    joined = " ".join(words)
    phrase_rules = {
        "حرق درجه اولى": ["first degree burn", "superficial burn"],
        "حرق درجه ثانيه": ["second degree burn", "partial thickness burn"],
        "حرق درجه ثالثه": ["third degree burn", "full thickness burn"],
        "حرق كهربا": ["electrical burn"],
        "حرق كيميائي": ["chemical burn"],
        "اتحرق": ["burn", "burns", "burning"],
        "مش بيتنفس": ["not breathing", "resuscitation", "airway"],
        "لا يتنفس": ["not breathing", "resuscitation", "airway"],
        "تنفسه واقف": ["not breathing", "resuscitation", "airway"],
        "مش بيرضع": ["not feeding", "newborn infection", "sepsis"],
        "لا يرضع": ["not feeding", "newborn infection", "sepsis"],
        "نزيف بعد الولاده": ["postpartum hemorrhage", "bleeding after birth"],
        "نزيف بعد الولادة": ["postpartum hemorrhage", "bleeding after birth"],
        "طلق ناري": ["gunshot wound"],
        "رصاصه": ["gunshot wound", "bullet"],
        "مش واعي": ["unconscious", "collapse", "airway"],
        "فقد الوعي": ["unconscious", "collapse"],
        "مغمي عليه": ["unconscious", "collapse"],
    }
    for phrase, vals in phrase_rules.items():
        if phrase in joined:
            english_terms.extend(vals)
    seen, out = set(), []
    for x in english_terms:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return words, out


def text_scan(question: str, top_k: int):
    qn = normalize_arabic(question) if is_arabic(question) else question.lower()
    words = [w for w in qn.split() if len(w) >= 3]
    if not words:
        return []
    scored = []
    for chunk in raw_chunks:
        cn = normalize_arabic(chunk["text"]) if is_arabic(question) else chunk["text"].lower()
        score = 0
        matched = []
        for w in words:
            c = cn.count(w)
            if c:
                score += c
                matched.append(w)
        if score > 0:
            scored.append({
                "source": chunk["source"],
                "text": chunk["text"],
                "score": round(float(score), 3),
                "method": "text-scan",
                "matched_terms": matched[:8],
            })
    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:top_k]


def keyword_search(query_str: str, top_k: int):
    if ix is None:
        return []
    from whoosh.qparser import MultifieldParser, OrGroup
    from whoosh import scoring
    clean = re.sub(r'[^\x00-\x7F]', ' ', query_str).strip()
    clean = re.sub(r'\s+', ' ', clean)
    if not clean:
        return []
    out = []
    try:
        with ix.searcher(weighting=scoring.BM25F()) as s:
            q = MultifieldParser(["content"], ix.schema, group=OrGroup).parse(clean)
            for r in s.search(q, limit=top_k):
                out.append({
                    "source": r["source"],
                    "text": r["content"],
                    "score": round(float(r.score), 3),
                    "method": "keyword",
                    "matched_terms": clean.split()[:8],
                })
    except Exception as e:
        print(f"Keyword search error: {e}")
    return out


def dedupe(results, top_k):
    seen = set()
    out = []
    for r in results:
        key = (r["source"], r["text"][:160])
        if key not in seen:
            seen.add(key)
            out.append(r)
        if len(out) >= top_k:
            break
    return out


def search(question: str, top_k: int):
    results = []
    if is_arabic(question):
        ar_words, en_terms = arabic_keywords(question)
        results.extend(text_scan(question, top_k))
        if en_terms:
            results.extend(keyword_search(" ".join(en_terms), top_k))
        qn = normalize_arabic(question)
        if any(k in qn for k in ["حرق", "حروق", "انفجار", "فوسفور", "كيميائي", "كهربائي"]):
            results.extend(keyword_search(
                "burn burns treatment airway inhalation chemical electrical phosphorus",
                min(8, top_k + 2)
            ))
        results = dedupe(sorted(results, key=lambda x: x["score"], reverse=True), top_k)
    else:
        results.extend(keyword_search(question, top_k))
        if len(results) < top_k:
            results.extend(text_scan(question, top_k))
        results = dedupe(sorted(results, key=lambda x: x["score"], reverse=True), top_k)

    strong = [r for r in results if r["score"] >= 1]
    return strong[:top_k] if strong else []


def build_prompt(question: str, chunks):
    arabic = is_arabic(question)

    if arabic:
        system_prompt = SYSTEM_PROMPT_AR
        no_info = "هذه المعلومات غير متوفرة في الوثائق المتاحة."
        lang_instruction = (
            "تعليمات اللغة: يجب أن تكتب إجابتك كاملةً باللغة العربية فقط. "
            "المرجع الطبي مكتوب بالإنجليزية لكن إجابتك يجب أن تكون بالعربية. "
            "ممنوع منعاً باتاً استخدام الإنجليزية في الإجابة."
        )
        question_label = "السؤال"
        answer_label = "الإجابة بالعربية"
    else:
        system_prompt = SYSTEM_PROMPT_EN
        no_info = "This information is not available in the provided documents."
        lang_instruction = "Language: Answer in English only."
        question_label = "QUESTION"
        answer_label = "ANSWER"

    if not chunks:
        context = "NO_RELEVANT_CONTEXT"
    else:
        context = "\n\n---\n\n".join(
            f"[Source: {c['source']} | score={c['score']} | method={c['method']}]\n{c['text']}"
            for c in chunks
        )

    if arabic:
        user_msg = f"""المرجع الطبي (مكتوب بالإنجليزية — اقرأه وأجب بالعربية):
{context}

{lang_instruction}

{question_label}: {question}

تعليمات الإجابة:
- استخدم المرجع الطبي أعلاه فقط.
- إذا كان المرجع غير كافٍ، اكتب بالضبط: {no_info}
- لا تستنتج تشخيصات أو علاجات غير مذكورة.
- استخدم نقاط مختصرة للإجراءات.
- كن موجزاً — 5 نقاط كحد أقصى.
- تذكر: الإجابة بالعربية فقط.

{answer_label}:"""
    else:
        user_msg = f"""MEDICAL REFERENCE:
{context}

{lang_instruction}

{question_label}: {question}

Instructions for the final answer:
- Use only the MEDICAL REFERENCE above.
- If the reference is missing or insufficient, output exactly: {no_info}
- Do not infer extra diagnosis, causes, or treatment.
- Prefer short bullet points when listing actions.
- Keep the answer focused on the question only.
- Be CONCISE — maximum 5 bullet points.

{answer_label}:"""

    return (
        f"<start_of_turn>system\n{system_prompt}<end_of_turn>\n"
        f"<start_of_turn>user\n{user_msg}<end_of_turn>\n"
        f"<start_of_turn>model\n"
    )


def est_tok(text: str):
    ar = len(re.findall(r'[\u0600-\u06FF]', text))
    return max(1, int(ar / 2 + (len(text) - ar) / 4))


def extract_thinking_and_answer(raw: str):
    raw = raw.strip()
    think = ""
    answer = raw
    m = re.search(r'<think>\s*(.*?)\s*</think>\s*(.*)', raw, re.DOTALL | re.IGNORECASE)
    if m:
        think = m.group(1).strip()
        answer = m.group(2).strip()
    answer = re.sub(r'<[^>]+>', '', answer).strip()
    answer = re.sub(r'^(model|assistant)\s*', '', answer, flags=re.IGNORECASE).strip()
    return think, answer


def build_trace(question, chunks):
    lines = [
        f"language = {'arabic' if is_arabic(question) else 'english'}",
        f"retrieved_chunks = {len(chunks)}",
    ]
    for i, c in enumerate(chunks, 1):
        matched = ", ".join(c.get("matched_terms", [])[:6]) or "-"
        lines.append(
            f"{i}. source={c['source']} | method={c['method']} | score={c['score']} | matched={matched}"
        )
    if not chunks:
        lines.append("No sufficiently relevant chunks were found.")
    return "\n".join(lines)

def call_llama(prompt: str, max_tokens: int, temperature: float):
    payload = json.dumps({
        "prompt": prompt,

        # ✅ Gemma settings
        "n_predict": max_tokens,
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 64,

        # ✅ IMPORTANT for Gemma
        "stop": ["<turn|>"],

        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        LLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=120) as r:
        result = json.loads(r.read().decode("utf-8"))

    raw = result.get("content", "").strip()
    think, answer = extract_thinking_and_answer(raw)

    p_tok = result.get("tokens_evaluated", est_tok(prompt))
    c_tok = result.get("tokens_predicted", est_tok(answer))

    return answer, think, p_tok, c_tok

def check_llama_alive() -> bool:
    try:
        with urllib.request.urlopen(LLAMA_HEALTH, timeout=2) as r:
            return r.status == 200
    except Exception:
        return False


# ── Flask routes ──────────────────────────────────────────────────────────────

@app.after_request
def cors(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    resp.headers["Access-Control-Allow-Methods"] = "POST,GET,OPTIONS"
    return resp


@app.route("/ask", methods=["OPTIONS"])
@app.route("/health", methods=["OPTIONS"])
def options():
    return Response(status=200)


@app.route("/health")
def health():
    """
    Returns RAG status independently of llama.
    The frontend shows two separate dots: RAG (this server) and llama.
    """
    llama_ok = check_llama_alive()
    return jsonify({
        "status": "ok",           # RAG server itself is always ok if you reach here
        "chunks": len(raw_chunks),
        "index": ix is not None,
        "llama_alive": llama_ok,
    })


@app.route("/ask", methods=["POST"])
def ask():
    data = request.get_json(force=True)
    question    = data.get("question", "").strip()
    max_tokens  = int(data.get("max_tokens", DEFAULT_MAX_TOKENS))
    temperature = float(data.get("temperature", DEFAULT_TEMPERATURE))
    top_k       = int(data.get("top_k", DEFAULT_TOP_K))

    if not question:
        return jsonify({"error": "empty question"}), 400

    # ── Retrieval ─────────────────────────────────────────────────────────────
    chunks = search(question, top_k)
    prompt = build_prompt(question, chunks)
    trace  = build_trace(question, chunks)

    print(f"\n🔍 Q: {question[:120]}")
    print(f"   chunks={len(chunks)}  max_tok={max_tokens}  temp={temperature}")

    # ── Check llama before trying ─────────────────────────────────────────────
    if not check_llama_alive():
        return jsonify({
            "error": (
                "llama.cpp server is not running on port 8080.\n\n"
                "Start it with:\n"
                "  .\\llama-server.exe -m your_model.gguf --port 8080 "
                "--ctx-size 2048 --threads 4\n\n"
                "Or run: start_llama.bat"
            )
        }), 503

    try:
        answer, model_thinking, p_tok, c_tok = call_llama(prompt, max_tokens, temperature)
    except urllib.error.URLError as e:
        return jsonify({"error": f"Cannot reach llama.cpp: {e}"}), 503
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    visible_thinking = model_thinking.strip() if model_thinking.strip() else trace
    print(f"   ✅ answer: {answer[:80]}")

    return jsonify({
        "answer":   answer,
        "thinking": visible_thinking,
        "chunks":   chunks,
        "lang":     "arabic" if is_arabic(question) else "english",
        "tokens":   {"prompt": p_tok, "completion": c_tok, "total": p_tok + c_tok},
    })


if __name__ == "__main__":
    print("\n" + "═" * 55)
    print("  🏥  Grounded RAG Server — port", PORT)
    print("═" * 55)
    load()
    print(f"\n  Llama server expected at : {LLAMA_URL}")
    print(f"  Open browser at          : http://localhost:{PORT}")
    print(f"  Default max_tokens       : {DEFAULT_MAX_TOKENS}  (lower = faster)")
    print("═" * 55 + "\n")
    app.run(host="0.0.0.0", port=PORT, debug=False)
