"""
rag_server_fixed.py
Fixes:
- Separate health checks: RAG status independent of llama status
- Faster response: reduced default tokens + lower timeout
- Better CORS + OPTIONS handling
- Startup diagnostics
- Graceful llama.cpp connection errors (won't crash server)
"""

import json, os, re, sys, unicodedata, urllib.request, urllib.error, base64, mimetypes, time, wave, subprocess, uuid, tempfile

try:
    from flask import Flask, request, jsonify, Response, send_from_directory, send_file
except ImportError:
    print("Run: python -m pip install flask")
    sys.exit(1)

try:
    from faster_whisper import WhisperModel
except ImportError:
    print("Run: py -m pip install faster-whisper")
    sys.exit(1)

LLAMA_URL   = "http://localhost:8080/completion"
LLAMA_HEALTH = "http://localhost:8080/health"
INDEX_DIR   = "search_index"
CHUNKS_FILE = "chunks.json"
PORT        = 8081

# Voice input settings
AUDIO_UPLOAD_DIR = "voice_uploads"

# STT model: English now. Later Arabic = change to a multilingual Whisper model.
# Use a multilingual Whisper model by default so Arabic speech works.
# English-only models end with .en; do NOT use tiny.en/small.en for Arabic.
WHISPER_MODEL_NAME = os.environ.get("WHISPER_MODEL_NAME", "tiny").strip()
WHISPER_LANGUAGE = os.environ.get("WHISPER_LANGUAGE", "auto").strip().lower()  # auto | en | ar
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cpu").strip()
WHISPER_COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "int8").strip()

# TTS settings: Piper offline text-to-speech
# Your current folder structure:
#   D:\rag_system\piper\piper\piper.exe
#   D:\rag_system\piper\voices\en_US-lessac-medium.onnx
PIPER_EXE = os.environ.get("PIPER_EXE", r"piper\piper\piper.exe").strip()
PIPER_VOICE = os.environ.get("PIPER_VOICE", r"piper\voices\en_US-lessac-medium.onnx").strip()
# Optional Arabic Piper/Sherpa-compatible voice model. Leave empty until you download one.
# If empty, Arabic answers will still appear as text, but TTS will be skipped instead of speaking broken English.
PIPER_VOICE_AR = os.environ.get("PIPER_VOICE_AR", r"piper\voices_ar\ar_JO-kareem-low.onnx").strip()
TTS_OUTPUT_DIR = os.environ.get("TTS_OUTPUT_DIR", r"tts_outputs").strip()
ENABLE_TTS_DEFAULT = os.environ.get("ENABLE_TTS_DEFAULT", "1").strip() not in {"0", "false", "False", "no", "NO"}

# Arabic output voice engine.
# nipponjo/tts_arabic gave better Arabic samples for your app and worked after installing gdown==4.7.3.
# speaker=3 corresponds to the preferred sample speaker you chose.
ARABIC_TTS_ENGINE = os.environ.get("ARABIC_TTS_ENGINE", "tts_arabic").strip().lower()  # tts_arabic | piper
TTS_ARABIC_SPEAKER = int(os.environ.get("TTS_ARABIC_SPEAKER", "3"))
TTS_ARABIC_PACE = float(os.environ.get("TTS_ARABIC_PACE", "0.9"))
TTS_ARABIC_VOWELIZER = os.environ.get("TTS_ARABIC_VOWELIZER", "shakkelha").strip()

# Optional: old experimental Gemma-audio config kept for later, but current working path uses Whisper STT.
GEMMA_AUDIO_CHAT_URL = os.environ.get("GEMMA_AUDIO_CHAT_URL", "").strip()
GEMMA_AUDIO_MODEL    = os.environ.get("GEMMA_AUDIO_MODEL", "gemma-audio").strip()

# ── Speed tip: reduce n_predict default, Gemma 4 is slow on CPU ──────────────
DEFAULT_MAX_TOKENS  = 350   # good balance between speed and quality
DEFAULT_TEMPERATURE = 0.05
DEFAULT_TOP_K       = 5     # 5 chunks gives richer context without being too slow
SYSTEM_PROMPT_EN = """You are Rescate, an intelligent offline medical emergency and survival assistant designed for disaster zones, refugee camps, remote medicine, and low-resource environments.

Your role is to provide detailed, calm, educational, medically grounded answers using ONLY the provided medical context and reference material.

Your writing style is EXTREMELY IMPORTANT.

The answer should sound like a knowledgeable medical educator naturally explaining the situation step-by-step in connected paragraphs.

Use transitional phrases naturally throughout the response, such as:
- “First of all,”
- “In this situation,”
- “One important thing to understand is…”
- “As the condition progresses…”
- “Another important point is…”
- “In summary,”
- “Because of this…”
- “For example,”
- “If the situation becomes severe…”

The response should feel human, explanatory, and medically thoughtful — NOT robotic, short, or list-like.

Rules:
- Use ONLY information grounded in the provided medical context.
- Never invent medical facts.
- If the exact information is unavailable, clearly state:
  “This information is not available in the provided documents.”
- Write in long explanatory paragraphs.
- Expand naturally on causes, symptoms, risks, progression, complications, and practical management.
- Explain WHY things happen medically when possible.
- Connect ideas together smoothly.
- Avoid extremely short answers.
- Avoid bullet points unless absolutely necessary for emergency steps.
- Do NOT mention prompts, instructions, references, retrieval systems, chunks, or documents.
- Do NOT repeat the same sentence structure.
- Maintain a calm, intelligent, medically professional tone.
- Prioritize educational clarity and realism.

For emergency situations:
Explain:
1. What is happening medically
2. What immediate actions should be taken
3. What symptoms or warning signs matter
4. What complications may happen
5. When urgent medical care becomes necessary

The response should resemble a high-quality medical educational explanation rather than a chatbot response."""
SYSTEM_PROMPT_AR = """أنت Rescate، مساعد طبي ذكي يعمل بدون إنترنت ومصمم لحالات الطوارئ والكوارث والمخيمات والمناطق ذات الموارد المحدودة.

مهمتك هي تقديم إجابات طبية مفصلة وهادئة ومبنية فقط على المعلومات الطبية الموجودة في السياق المرفق.

أسلوب الكتابة مهم جدًا.

يجب أن تبدو الإجابة وكأن طبيبًا أو مُثقفًا طبيًا يشرح الحالة بهدوء وبأسلوب مترابط خطوة بخطوة.

استخدم عبارات انتقالية بشكل طبيعي أثناء الشرح مثل:
- "أولًا،"
- "في هذه الحالة،"
- "من المهم أن نفهم أن..."
- "مع تطور الحالة..."
- "نقطة مهمة أخرى هي..."
- "على سبيل المثال،"
- "بسبب ذلك..."
- "في الحالات الشديدة..."
- "في النهاية،"

يجب أن تكون الإجابة بشرية وطبيعية وشرحها مترابط، وليست قصيرة أو آلية أو مجرد نقاط منفصلة.

القواعد:
- استخدم فقط المعلومات الموجودة في السياق الطبي المرفق.
- لا تخترع أي معلومات طبية.
- إذا لم تكن المعلومة متوفرة بوضوح، قل:
  "هذه المعلومة غير متوفرة في المستندات المتاحة.
- اكتب في فقرات شرح طويلة نسبيًا.
- اشرح الأسباب والأعراض والمضاعفات وتطور الحالة بشكل طبيعي.
- حاول توضيح لماذا تحدث الأعراض أو المضاعفات طبيًا عندما يكون ذلك ممكنًا.
- اربط الأفكار ببعضها بسلاسة.
- لا تجعل الإجابة قصيرة جدًا.
- لا تستخدم نقاط إلا إذا كانت الحالة تتطلب خطوات إسعافية واضحة.
- لا تذكر النظام أو التعليمات أو المستندات أو الـRAG أو الـchunks.
- لا تكرر نفس الجمل أو نفس الصياغة.
- حافظ على نبرة طبية هادئة واحترافية وواضحة.
- اجعل الإجابة أقرب لشرح طبي تعليمي حقيقي وليس رد شات بوت.

في الحالات الطارئة:
اشرح:
1. ما الذي يحدث طبيًا
2. ما الذي يجب فعله فورًا
3. العلامات أو الأعراض المهمة
4. المضاعفات المحتملة
5. متى تصبح المساعدة الطبية العاجلة ضرورية

يجب أن تبدو الإجابة كشرح طبي واقعي ومترابط وغني بالمعلومات."""
app = Flask(__name__)
raw_chunks = []
ix = None

print(f"🎙 Loading Whisper STT model: {WHISPER_MODEL_NAME} ({WHISPER_DEVICE}/{WHISPER_COMPUTE_TYPE})")
whisper_model = WhisperModel(WHISPER_MODEL_NAME, device=WHISPER_DEVICE, compute_type=WHISPER_COMPUTE_TYPE)
print("✅ Whisper STT model loaded")

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

    # ── Chronic diseases / Diabetes ───────────────────────────────────────────
    "سكري": ["diabetes", "diabetic", "blood sugar", "glucose"],
    "سكر": ["diabetes", "blood sugar", "glucose"],
    "سكرية": ["diabetes", "diabetic"],
    "انسولين": ["insulin", "diabetes"],
    "جلوكوز": ["glucose", "blood sugar", "hypoglycemia"],
    "هبوط سكر": ["hypoglycemia", "low blood sugar", "glucose"],
    "هبوط": ["hypoglycemia", "low blood sugar", "fainting"],
    "ارتفاع سكر": ["hyperglycemia", "high blood sugar", "DKA"],
    "كيتو": ["ketoacidosis", "DKA", "diabetes"],
    "حماض": ["ketoacidosis", "DKA", "acidosis"],
    "ضغط": ["blood pressure", "hypertension"],
    "ضغط الدم": ["blood pressure", "hypertension"],
    "ضغط عالي": ["hypertension", "high blood pressure"],
    "ارتفاع الضغط": ["hypertension", "high blood pressure"],
    "انخفاض الضغط": ["hypotension", "low blood pressure", "shock"],
    "قصور القلب": ["heart failure", "cardiac failure"],
    "فشل القلب": ["heart failure", "cardiac failure"],
    "وذمة": ["edema", "swelling", "heart failure"],
    "ربو": ["asthma", "bronchospasm", "breathing"],
    "ربو القصبات": ["asthma", "bronchospasm"],
    "صرع": ["seizure", "epilepsy", "convulsion"],
    "نوبة صرع": ["seizure", "epilepsy", "status epilepticus"],
    "اختلاج": ["seizure", "convulsion"],
    "غدة درقية": ["thyroid", "hypothyroidism"],
    "خمول الغدة": ["hypothyroidism", "thyroid"],
    "غيبوبة": ["coma", "unconscious", "myxedema"],
    "غيبوبه": ["coma", "unconscious"],
    "افاقه": ["recovery", "regain consciousness"],

    # ── Neurological ─────────────────────────────────────────────────────────
    "سكتة": ["stroke", "brain emergency"],
    "سكتة دماغية": ["stroke", "cerebral", "CVA"],
    "جلطة دماغية": ["stroke", "cerebral infarction"],
    "احتشاء": ["infarction", "stroke", "myocardial infarction"],
    "شلل نصف": ["hemiplegia", "stroke", "paralysis"],
    "وجه مائل": ["facial droop", "stroke", "FAST"],
    "يد ضعيفة": ["arm weakness", "stroke", "FAST"],
    "كلام مش واضح": ["slurred speech", "stroke", "FAST"],
    "صداع شديد": ["severe headache", "meningitis", "stroke", "subarachnoid"],
    "صداع": ["headache", "meningitis", "stroke"],
    "رقبة متصلبة": ["neck stiffness", "meningitis"],
    "تيبس الرقبة": ["neck stiffness", "meningitis"],
    "تصلب الرقبة": ["neck stiffness", "meningitis"],
    "حساسية للضوء": ["photophobia", "meningitis"],
    "طفح": ["rash", "meningococcal", "meningitis"],
    "طفح جلدي": ["rash", "meningococcal", "petechiae"],
    "بقع حمراء": ["petechiae", "meningococcal", "rash"],
    "التهاب السحايا": ["meningitis", "meningococcal"],
    "سحايا": ["meningitis"],
    "ارتجاج": ["concussion", "head injury", "TBI"],
    "ضربة رأس": ["head injury", "concussion", "TBI"],
    "اصابة الرأس": ["head injury", "TBI", "concussion"],
    "مقياس جلاسكو": ["GCS", "glasgow coma scale", "head injury"],
    "ضعف في المخ": ["brain injury", "stroke", "head injury"],
    "نزيف مخي": ["intracranial hemorrhage", "brain bleed", "head injury"],
    "عين مختلفة": ["unequal pupils", "herniation", "head injury"],
    "حدقة": ["pupil", "eye", "head injury"],

    # ── Mental health / Shock ─────────────────────────────────────────────────
    "نزيف شديد": ["hemorrhage", "hypovolemic shock", "blood loss"],
    "صدمة دموية": ["hypovolemic shock", "hemorrhage", "blood loss"],
    "نزف": ["bleeding", "hemorrhage", "blood loss"],
    "ضاغط": ["tourniquet", "hemorrhage control"],
    "حزام الضغط": ["tourniquet", "pressure", "hemorrhage"],
    "ضغط مباشر": ["direct pressure", "wound", "bleeding"],
    "توتر": ["stress", "anxiety", "acute stress reaction"],
    "صدمة نفسية": ["trauma", "PTSD", "psychological"],
    "اضطراب ما بعد الصدمة": ["PTSD", "trauma", "mental health"],
    "كآبة": ["depression", "grief", "mental health"],
    "اكتئاب": ["depression", "mental health"],
    "انتحار": ["suicide", "suicidal", "mental health"],
    "يريد ان يموت": ["suicidal ideation", "suicide risk"],
    "حزن": ["grief", "bereavement", "mental health"],
    "فقدان": ["loss", "grief", "bereavement"],
    "هلوسة": ["hallucination", "psychosis", "mental health"],
    "جنون": ["psychosis", "mental health"],
    "ذهان": ["psychosis", "delusion"],
    "وسواس": ["anxiety", "OCD", "mental health"],
    "اسعافات نفسية": ["psychological first aid", "PFA", "mental health"],

    # ── Poisoning / Toxicology ────────────────────────────────────────────────
    "سم": ["poison", "poisoning", "toxic"],
    "تسمم": ["poisoning", "toxic", "poison"],
    "مبيد": ["pesticide", "organophosphate", "poisoning"],
    "مبيدات": ["pesticide", "organophosphate", "poisoning"],
    "مبيد حشري": ["insecticide", "organophosphate", "SLUDGE"],
    "اعصاب": ["nerve agent", "organophosphate", "chemical weapon"],
    "غاز اعصاب": ["nerve agent", "sarin", "chemical weapon"],
    "سارين": ["sarin", "nerve agent", "organophosphate"],
    "اوكسيد الكربون": ["carbon monoxide", "CO poisoning"],
    "غاز الكربون": ["carbon monoxide", "CO poisoning"],
    "احتراق": ["combustion", "carbon monoxide", "inhalation"],
    "مولد كهرباء": ["generator", "carbon monoxide", "CO poisoning"],
    "لدغة": ["bite", "snakebite", "envenomation"],
    "لسعة ثعبان": ["snakebite", "venom", "envenomation"],
    "ثعبان": ["snake", "snakebite", "venom"],
    "افعى": ["viper", "snakebite", "venom"],
    "عقرب": ["scorpion", "envenomation", "sting"],
    "حمض": ["acid", "corrosive", "chemical burn"],
    "حامض": ["acid", "corrosive"],
    "قلوي": ["alkali", "corrosive", "chemical burn"],
    "بلع": ["ingestion", "swallowing", "poisoning"],
    "ابتلع": ["ingested", "swallowed", "poisoning"],
    "كحول": ["alcohol", "poisoning"],
    "فحم نشط": ["activated charcoal", "poisoning treatment"],
    "يتقيأ": ["vomiting", "poisoning", "nausea"],
    "قيء": ["vomiting", "poisoning", "nausea"],
    "غثيان": ["nausea", "vomiting", "poisoning"],

    # ── GI / Musculoskeletal ──────────────────────────────────────────────────
    "بطن حاد": ["acute abdomen", "peritonitis", "surgical emergency"],
    "زائدة": ["appendicitis", "acute abdomen"],
    "انتان": ["peritonitis", "infection", "acute abdomen"],
    "التهاب الزائدة": ["appendicitis", "acute abdomen"],
    "التهاب الصفاق": ["peritonitis", "acute abdomen"],
    "انسداد معوي": ["intestinal obstruction", "bowel obstruction"],
    "انسداد": ["obstruction", "bowel obstruction", "airway"],
    "حمل خارج الرحم": ["ectopic pregnancy", "acute abdomen"],
    "اسهال": ["diarrhea", "dehydration"],
    "اسهاله": ["diarrhea", "dehydration"],
    "اسهالات": ["diarrhea", "dehydration", "cholera"],
    "كوليرا": ["cholera", "diarrhea", "dehydration"],
    "محلول الإماهة": ["ORS", "oral rehydration", "dehydration"],
    "محلول إماهة": ["ORS", "rehydration", "dehydration"],
    "جفاف شديد": ["severe dehydration", "IV fluids", "shock"],
    "التواء": ["sprain", "strain", "musculoskeletal"],
    "خلع كتف": ["shoulder dislocation", "dislocation"],
    "ظهر": ["back", "spine", "back pain"],
    "ألم الظهر": ["back pain", "spine", "lumbar"],
    "نخاع شوكي": ["spinal cord", "spine", "cauda equina"],
    "ذيل الفرس": ["cauda equina", "spine", "emergency"],

    # ── Breathing / Chest (additional) ────────────────────────────────────────
    "ذبحة": ["angina", "chest pain", "cardiac"],
    "احتشاء قلب": ["myocardial infarction", "heart attack", "chest pain"],
    "نوبة قلبية": ["heart attack", "myocardial infarction", "cardiac arrest"],
    "توقف القلب": ["cardiac arrest", "CPR", "resuscitation"],
    "استرواح": ["pneumothorax", "chest", "breathing"],
    "استرواح صدري": ["pneumothorax", "tension pneumothorax"],
    "ضغط مجوف": ["tension pneumothorax", "needle decompression"],
    "جرح الصدر": ["chest wound", "open chest wound", "sucking chest wound"],
    "جروح الصدر": ["chest wound", "penetrating chest", "pneumothorax"],
    "كسر الضلوع": ["rib fracture", "chest trauma", "flail chest"],
    "ضلوع": ["ribs", "rib fracture", "chest"],
    "التهاب رئوي": ["pneumonia", "lung infection", "respiratory"],
    "التهاب الرئة": ["pneumonia", "lung infection"],
    "ذات الرئة": ["pneumonia", "lung infection"],

    # ── Fractures (additional) ─────────────────────────────────────────────────
    "جبيرة": ["splint", "immobilization", "fracture"],
    "جبس": ["cast", "plaster", "fracture"],
    "كسر مفتوح": ["open fracture", "compound fracture"],
    "كسر مركب": ["compound fracture", "open fracture"],
    "ورك": ["hip", "hip fracture", "pelvis"],
    "حوض": ["pelvis", "pelvic fracture", "hemorrhage"],
    "فخذ": ["femur", "thigh", "femur fracture"],
    "كعب": ["ankle", "ankle fracture", "sprain"],
    "متلازمة الحجرة": ["compartment syndrome", "fracture complication"],
    "انسداد وعاء": ["vascular compromise", "ischemia", "compartment"],
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
        # Burns
        "حرق درجه اولى": ["first degree burn", "superficial burn"],
        "حرق درجه ثانيه": ["second degree burn", "partial thickness burn"],
        "حرق درجه ثالثه": ["third degree burn", "full thickness burn"],
        "حرق كهربا": ["electrical burn"],
        "حرق كيميائي": ["chemical burn"],
        "اتحرق": ["burn", "burns", "burning"],
        # Breathing
        "مش بيتنفس": ["not breathing", "resuscitation", "airway"],
        "لا يتنفس": ["not breathing", "resuscitation", "airway"],
        "تنفسه واقف": ["not breathing", "resuscitation", "airway"],
        # Pediatric
        "مش بيرضع": ["not feeding", "newborn infection", "sepsis"],
        "لا يرضع": ["not feeding", "newborn infection", "sepsis"],
        # Obstetric
        "نزيف بعد الولاده": ["postpartum hemorrhage", "bleeding after birth"],
        "نزيف بعد الولادة": ["postpartum hemorrhage", "bleeding after birth"],
        # Trauma
        "طلق ناري": ["gunshot wound"],
        "رصاصه": ["gunshot wound", "bullet"],
        # Consciousness
        "مش واعي": ["unconscious", "collapse", "airway"],
        "فقد الوعي": ["unconscious", "collapse"],
        "مغمي عليه": ["unconscious", "collapse"],
        # Neurological
        "سكتة دماغية": ["stroke", "CVA", "FAST"],
        "جلطة دماغية": ["stroke", "cerebral infarction"],
        "نوبة صرع": ["seizure", "epilepsy", "status epilepticus"],
        "التهاب السحايا": ["meningitis", "neck stiffness", "antibiotics"],
        "رقبة متصلبة": ["neck stiffness", "meningitis"],
        "ضربة رأس": ["head injury", "concussion", "GCS"],
        # Chronic
        "هبوط سكر": ["hypoglycemia", "low blood sugar", "glucose"],
        "ارتفاع سكر": ["hyperglycemia", "high blood sugar", "DKA"],
        "ضغط عالي": ["hypertension", "high blood pressure"],
        "قصور القلب": ["heart failure", "pulmonary edema"],
        "نوبة ربو": ["asthma attack", "bronchospasm", "salbutamol"],
        # Poisoning
        "تسمم بغاز": ["gas poisoning", "carbon monoxide", "inhalation"],
        "مبيد حشري": ["insecticide", "organophosphate", "SLUDGE"],
        "لدغة ثعبان": ["snakebite", "venom", "antivenom"],
        "بلع مواد": ["ingested chemical", "corrosive ingestion", "poisoning"],
        # GI
        "بطن حاد": ["acute abdomen", "peritonitis", "surgical emergency"],
        "اسهال شديد": ["severe diarrhea", "dehydration", "cholera"],
        "جفاف شديد": ["severe dehydration", "IV fluids", "shock"],
        # Mental health
        "صدمة نفسية": ["PTSD", "trauma", "psychological first aid"],
        "افكار انتحارية": ["suicidal ideation", "suicide risk", "mental health"],
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


EN_STOPWORDS = {
    "a","an","the","and","or","but","if","then","to","of","in","on","for","with","without",
    "my","me","i","you","your","we","our","is","are","was","were","be","been","being",
    "has","have","had","having","do","does","did","what","how","when","where","why",
    "help","out","please","can","could","should","would","someone","person","patient",
    "very","severe","serious","really","now","right","tell","need"
}

EN_EXPANSIONS = {
    # Pediatric
    "baby": ["baby", "infant", "newborn", "neonate", "child"],
    "infant": ["infant", "baby", "newborn", "neonate"],
    "newborn": ["newborn", "neonate", "baby", "infant"],
    # Vital signs
    "fever": ["fever", "high temperature", "temperature", "hot", "febrile"],
    "hypothermia": ["hypothermia", "cold", "low temperature", "warming", "warm", "skin-to-skin"],
    "cold": ["cold", "hypothermia", "low temperature", "warming", "warm"],
    # Trauma
    "bleeding": ["bleeding", "hemorrhage", "blood loss", "haemorrhage"],
    "burn": ["burn", "burns", "burning", "thermal injury"],
    "choking": ["choking", "airway", "obstruction", "not breathing"],
    "fracture": ["fracture", "broken bone", "immobilization", "splint"],
    "shock": ["shock", "hemorrhage", "hypovolemic", "blood loss", "hypotension"],
    "wound": ["wound", "laceration", "injury", "bleeding", "hemorrhage"],
    "crush": ["crush injury", "compartment syndrome", "trauma"],
    "blast": ["blast injury", "explosion", "shrapnel", "trauma"],
    "dislocation": ["dislocation", "reduction", "joint injury"],
    "sprain": ["sprain", "strain", "RICE", "soft tissue"],
    # Breathing
    "breathing": ["breathing", "respiratory", "airway", "breath"],
    "asthma": ["asthma", "bronchospasm", "wheeze", "inhaler", "salbutamol"],
    "pneumonia": ["pneumonia", "lung infection", "respiratory", "CURB-65"],
    "pneumothorax": ["pneumothorax", "chest", "tension pneumothorax", "needle decompression"],
    "chest": ["chest", "thoracic", "pneumothorax", "rib", "lung"],
    # Neurological
    "stroke": ["stroke", "CVA", "FAST", "cerebral", "thrombolysis"],
    "seizure": ["seizure", "epilepsy", "convulsion", "status epilepticus"],
    "meningitis": ["meningitis", "meningococcal", "neck stiffness", "petechiae"],
    "headache": ["headache", "meningitis", "stroke", "subarachnoid"],
    "unconscious": ["unconscious", "loss of consciousness", "GCS", "coma"],
    "head": ["head injury", "TBI", "concussion", "GCS", "skull"],
    # Chronic disease
    "diabetes": ["diabetes", "diabetic", "hypoglycemia", "DKA", "insulin"],
    "diabetic": ["diabetic", "diabetes", "hypoglycemia", "blood sugar"],
    "hypoglycemia": ["hypoglycemia", "low blood sugar", "glucose", "sugar"],
    "hypertension": ["hypertension", "blood pressure", "BP", "stroke"],
    "heart": ["heart", "cardiac", "heart failure", "pulmonary edema"],
    "epilepsy": ["epilepsy", "seizure", "convulsion", "status epilepticus"],
    # Poisoning
    "poison": ["poison", "poisoning", "toxic", "toxidrome"],
    "poisoning": ["poisoning", "toxic", "antidote", "activated charcoal"],
    "snakebite": ["snakebite", "venom", "envenomation", "antivenom"],
    "snake": ["snake", "snakebite", "venom", "antivenom"],
    "organophosphate": ["organophosphate", "pesticide", "SLUDGE", "nerve agent", "atropine"],
    "carbon": ["carbon monoxide", "CO poisoning", "smoke inhalation", "oxygen"],
    "corrosive": ["corrosive", "acid", "alkali", "chemical burn"],
    # GI / Musculoskeletal
    "diarrhea": ["diarrhea", "dehydration", "ORS", "rehydration"],
    "dehydration": ["dehydration", "ORS", "rehydration", "fluids"],
    "abdomen": ["abdomen", "acute abdomen", "peritonitis", "appendicitis"],
    "back": ["back pain", "spine", "lumbar", "cauda equina"],
    # Mental health
    "suicide": ["suicide", "suicidal", "mental health", "crisis"],
    "ptsd": ["PTSD", "post-traumatic", "trauma", "mental health"],
    "psychosis": ["psychosis", "hallucination", "delusion", "mental health"],
    "grief": ["grief", "bereavement", "loss", "mental health"],
    "stress": ["stress", "acute stress reaction", "psychological first aid"],
}

def english_keywords(question: str):
    q = re.sub(r'[^A-Za-z0-9\s-]', ' ', (question or '').lower())
    words = [w for w in q.split() if len(w) >= 3 and w not in EN_STOPWORDS]
    terms = []
    for w in words:
        terms.append(w)
        if w in EN_EXPANSIONS:
            terms.extend(EN_EXPANSIONS[w])
    # phrase rules
    joined = " ".join(words)
    if "high" in words and ("temperature" in words or "fever" in words):
        terms.extend(["fever", "high temperature", "febrile", "hot"])
    if "baby" in words or "infant" in words or "newborn" in words:
        terms.extend(["newborn", "infant", "neonate", "baby"])
    if "low" in words and "blood" in words and "sugar" in words:
        terms.extend(["hypoglycemia", "low blood sugar", "glucose", "diabetes"])
    if "high" in words and "blood" in words and "pressure" in words:
        terms.extend(["hypertension", "high blood pressure", "BP"])
    if "chest" in words and "pain" in words:
        terms.extend(["chest pain", "myocardial infarction", "heart attack", "angina"])
    if "not" in words and "breathing" in words:
        terms.extend(["not breathing", "resuscitation", "airway", "CPR"])
    if "neck" in words and "stiff" in words:
        terms.extend(["neck stiffness", "meningitis", "meningococcal"])
    if "carbon" in words and "monoxide" in words:
        terms.extend(["carbon monoxide", "CO poisoning", "oxygen"])
    if "nerve" in words and "agent" in words:
        terms.extend(["nerve agent", "organophosphate", "sarin", "atropine"])
    if "snake" in words or "snakebite" in words:
        terms.extend(["snakebite", "venom", "antivenom", "envenomation"])
    if "sugar" in words and ("low" in words or "drop" in words):
        terms.extend(["hypoglycemia", "low blood sugar", "glucose"])
    if "heart" in words and ("failure" in words or "attack" in words):
        terms.extend(["heart failure", "cardiac", "myocardial infarction"])
    if "back" in words and "pain" in words:
        terms.extend(["back pain", "lumbar", "spine", "cauda equina"])
    if "suicid" in joined or "kill" in joined:
        terms.extend(["suicide", "suicidal ideation", "mental health"])
    if "head" in words and ("injury" in words or "trauma" in words or "hit" in words):
        terms.extend(["head injury", "TBI", "concussion", "GCS"])
    seen, out = set(), []
    for t in terms:
        t = t.strip()
        if t and t not in seen:
            seen.add(t); out.append(t)
    return out

def english_query(question: str):
    terms = english_keywords(question)
    return " ".join(terms) if terms else question

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
        # Boost specific medical domains with extra keyword injection
        if any(k in qn for k in ["حرق", "حروق", "انفجار", "فوسفور", "كيميائي", "كهربائي"]):
            results.extend(keyword_search(
                "burn burns treatment airway inhalation chemical electrical phosphorus",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["سكتة", "سكتة دماغية", "جلطة", "شلل", "وجه مائل", "كلام"]):
            results.extend(keyword_search(
                "stroke FAST facial droop arm weakness speech slurred thrombolysis",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["التهاب السحايا", "سحايا", "رقبة متصلبة", "تصلب الرقبة", "صداع شديد"]):
            results.extend(keyword_search(
                "meningitis neck stiffness photophobia petechiae meningococcal antibiotics",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["صرع", "تشنج", "نوبة", "اختلاج"]):
            results.extend(keyword_search(
                "seizure epilepsy convulsion status epilepticus recovery position",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["سكري", "انسولين", "هبوط سكر", "ارتفاع سكر", "حماض", "كيتو"]):
            results.extend(keyword_search(
                "diabetes hypoglycemia DKA insulin ketoacidosis blood sugar",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["ضغط", "ضغط الدم", "ضغط عالي"]):
            results.extend(keyword_search(
                "hypertension blood pressure stroke emergency treatment",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["تسمم", "مبيد", "غاز اعصاب", "اوكسيد الكربون", "ثعبان", "افعى", "حمض"]):
            results.extend(keyword_search(
                "poisoning organophosphate carbon monoxide snakebite corrosive toxic antidote",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["اسهال", "جفاف", "كوليرا", "بطن حاد", "زائدة"]):
            results.extend(keyword_search(
                "diarrhea dehydration ORS cholera acute abdomen peritonitis appendicitis",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["كسر", "عظم", "خلع", "التواء", "انسداد الحجرة"]):
            results.extend(keyword_search(
                "fracture splint immobilization dislocation compartment syndrome",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["انتحار", "صدمة نفسية", "اضطراب", "هلوسة", "ذهان"]):
            results.extend(keyword_search(
                "suicide PTSD psychosis mental health psychological first aid grief",
                min(8, top_k + 2)
            ))
        if any(k in qn for k in ["نزيف شديد", "صدمة دموية", "نزف"]):
            results.extend(keyword_search(
                "hemorrhage hypovolemic shock tourniquet direct pressure blood loss",
                min(8, top_k + 2)
            ))
        results = dedupe(sorted(results, key=lambda x: x["score"], reverse=True), top_k)
    else:
        q_expanded = english_query(question)
        results.extend(keyword_search(q_expanded, max(top_k, 6)))
        if len(results) < top_k:
            results.extend(text_scan(q_expanded, max(top_k, 6)))
        # fallback to original wording if expansion found too little
        if len(results) < max(2, top_k // 2):
            results.extend(keyword_search(question, top_k))
            results.extend(text_scan(question, top_k))
        results = dedupe(sorted(results, key=lambda x: x["score"], reverse=True), top_k)

    # Lower threshold so we always return something useful
    strong = [r for r in results if r["score"] >= 0.5]
    if strong:
        return strong[:top_k]
    # Last resort: return whatever we found, even low-score chunks
    if results:
        return results[:top_k]
    return []


def build_prompt(question: str, chunks):
    """
    Build a prompt that uses the rich paragraph-style system prompt.
    This restores the high-quality answer style from before voice integration.
    """
    arabic = is_arabic(question)
    system_prompt = SYSTEM_PROMPT_AR if arabic else SYSTEM_PROMPT_EN

    if arabic:
        no_info = "هذه المعلومة غير متوفرة في المحتوى الطبي المقدم."
        question_label = "السؤال"
        answer_label = "الإجابة بالعربية"
    else:
        no_info = "This information is not available in the provided documents."
        question_label = "QUESTION"
        answer_label = "ANSWER"

    def clean_chunk_text(t: str, limit: int = 800) -> str:
        t = re.sub(r'\s+', ' ', t or '').strip()
        if len(t) > limit:
            t = t[:limit].rsplit(' ', 1)[0] + '...'
        return t

    if not chunks:
        context = "NO_RELEVANT_CONTEXT"
    else:
        compact = []
        for i, c in enumerate(chunks[:5], 1):
            compact.append(
                f"[{i}] source={c.get('source','unknown')} score={c.get('score','?')}\n"
                f"{clean_chunk_text(c.get('text',''))}"
            )
        context = "\n\n---\n\n".join(compact)

    if arabic:
        user_msg = f"""المرجع الطبي:
{context}

{question_label}: {question}

التعليمات:
- أجب بالعربية فقط باستخدام المعلومات الموجودة في المرجع أعلاه.
- اذكر الخطوات العملية المحددة الموجودة في المرجع.
- لا تكرر نفس الجملة أو نفس الفكرة مرتين.
- إذا لم تكن المعلومات متوفرة اكتب: {no_info}

{answer_label}:"""
    else:
        user_msg = f"""MEDICAL REFERENCE:
{context}

{question_label}: {question}

Instructions:
- Answer using ONLY the specific facts in the reference above.
- State the concrete steps or signs mentioned in the reference.
- Do NOT repeat the same sentence or idea twice.
- If unavailable, write exactly: {no_info}

{answer_label}:"""

    return (
        f"<start_of_turn>system\n{system_prompt}<end_of_turn>\n"
        f"<start_of_turn>user\n{user_msg}<end_of_turn>\n"
        f"<start_of_turn>model\n"
    )


def est_tok(text: str):
    ar = len(re.findall(r'[\u0600-\u06FF]', text))
    return max(1, int(ar / 2 + (len(text) - ar) / 4))




def audio_metadata(path: str, mime: str):
    size = os.path.getsize(path) if os.path.exists(path) else 0
    meta = {"filename": os.path.basename(path), "mime": mime, "size_bytes": size}
    if path.lower().endswith('.wav'):
        try:
            with wave.open(path, 'rb') as w:
                frames = w.getnframes()
                rate = w.getframerate() or 1
                meta.update({
                    "duration_sec": round(frames / float(rate), 2),
                    "sample_rate": rate,
                    "channels": w.getnchannels(),
                    "sample_width_bytes": w.getsampwidth(),
                })
        except Exception:
            pass
    return meta


def build_audio_instruction(mode: str) -> str:
    if mode == "debug":
        return "Confirm that the audio was received. Do not answer medically."
    if mode == "answer":
        return "Listen to the user's audio question and answer it clearly in English. Return only the final answer."
    return "Transcribe the audio exactly in English. Return only the spoken words."


def call_gemma_audio_openai(audio_path: str, mime: str, mode: str, max_tokens: int, temperature: float):
    """
    Calls an OpenAI-compatible multimodal chat endpoint that supports audio_url content blocks.
    This is intended for Gemma audio served by vLLM or any compatible local server.
    """
    if not GEMMA_AUDIO_CHAT_URL:
        raise RuntimeError(
            "Audio was uploaded and saved correctly, but no Gemma audio server is configured.\n\n"
            "For now, use Debug mode to test microphone upload. To let Gemma understand audio, start an audio-capable Gemma server and set:\n"
            "  set GEMMA_AUDIO_CHAT_URL=http://localhost:8000/v1/chat/completions\n"
            "  set GEMMA_AUDIO_MODEL=your-gemma-audio-model-name\n\n"
            "Your current llama.cpp /completion endpoint is text-only in this app, so it cannot receive the recorded audio file directly."
        )

    with open(audio_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    data_url = f"data:{mime};base64,{b64}"

    payload = json.dumps({
        "model": GEMMA_AUDIO_MODEL,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": build_audio_instruction(mode)},
                    {"type": "audio_url", "audio_url": {"url": data_url}},
                ],
            }
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }).encode("utf-8")

    req = urllib.request.Request(
        GEMMA_AUDIO_CHAT_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        result = json.loads(r.read().decode("utf-8"))

    try:
        content = result["choices"][0]["message"]["content"]
    except Exception:
        content = json.dumps(result, ensure_ascii=False)

    if isinstance(content, list):
        text_parts = []
        for part in content:
            if isinstance(part, dict):
                text_parts.append(part.get("text") or part.get("content") or "")
            else:
                text_parts.append(str(part))
        content = "\n".join(x for x in text_parts if x).strip()

    usage = result.get("usage", {}) if isinstance(result, dict) else {}
    p_tok = usage.get("prompt_tokens", est_tok(build_audio_instruction(mode)))
    c_tok = usage.get("completion_tokens", est_tok(content))
    return content.strip(), p_tok, c_tok

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
    """
    llama.cpp /completion compatible call.
    FIX: removed the old Gemma stop token that caused HTTP 400 on your llama.cpp build.
    Also keeps payload minimal because your direct /completion test succeeded with this format.
    """
    payload = json.dumps({
        "prompt": prompt,
        "n_predict": max_tokens,
        "temperature": temperature,
        "top_p": 0.9,
        "top_k": 40,
        "repeat_penalty": 1.3,          # prevents looping / repetitive output
        "repeat_last_n": 128,           # look back 128 tokens for repetition
        "stop": ["<end_of_turn>", "<start_of_turn>", "\n\n\n"],
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        LLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=180) as r:
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



def safe_tts_text(text: str, limit: int = 1800) -> str:
    """Clean model output before sending it to Piper."""
    text = re.sub(r'<[^>]+>', ' ', text or '')
    text = re.sub(r'\*+', '', text)
    text = re.sub(r'`+', '', text)
    text = re.sub(r'#+\s*', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) > limit:
        text = text[:limit].rsplit(' ', 1)[0] + '.'
    return text

def split_tts_text(text: str, max_chars: int = 260):
    """Split long Arabic TTS text into small sentence groups to avoid ONNXRuntime RAM errors."""
    text = re.sub(r'\s+', ' ', text or '').strip()
    if not text:
        return []

    # Split after Arabic/English sentence punctuation while preserving readable chunks.
    sentences = re.split(r'(?<=[\.\!\?؟؛،])\s+', text)
    sentences = [s.strip() for s in sentences if s.strip()]

    # If punctuation is missing, force split by words.
    if len(sentences) <= 1 and len(text) > max_chars:
        words = text.split()
        chunks, cur = [], ""
        for w in words:
            nxt = (cur + " " + w).strip()
            if len(nxt) > max_chars and cur:
                chunks.append(cur.strip())
                cur = w
            else:
                cur = nxt
        if cur:
            chunks.append(cur.strip())
        return chunks

    chunks, cur = [], ""
    for sent in sentences:
        # Very long sentence: split it by words.
        if len(sent) > max_chars:
            if cur:
                chunks.append(cur.strip())
                cur = ""
            words = sent.split()
            part = ""
            for w in words:
                nxt = (part + " " + w).strip()
                if len(nxt) > max_chars and part:
                    chunks.append(part.strip())
                    part = w
                else:
                    part = nxt
            if part:
                chunks.append(part.strip())
            continue

        nxt = (cur + " " + sent).strip()
        if len(nxt) > max_chars and cur:
            chunks.append(cur.strip())
            cur = sent
        else:
            cur = nxt
    if cur:
        chunks.append(cur.strip())
    return chunks


def concat_wavs(input_paths, output_path: str):
    """Concatenate WAV files generated by the same TTS engine into one WAV."""
    input_paths = [p for p in input_paths if os.path.exists(p) and os.path.getsize(p) > 1000]
    if not input_paths:
        raise RuntimeError("No valid WAV parts to concatenate.")

    with wave.open(input_paths[0], 'rb') as first:
        params = first.getparams()
        frames = [first.readframes(first.getnframes())]

    for path in input_paths[1:]:
        with wave.open(path, 'rb') as w:
            if w.getnchannels() != params.nchannels or w.getsampwidth() != params.sampwidth or w.getframerate() != params.framerate:
                raise RuntimeError("WAV parts have incompatible audio format.")
            frames.append(w.readframes(w.getnframes()))

    with wave.open(output_path, 'wb') as out:
        out.setparams(params)
        for fr in frames:
            out.writeframes(fr)


def synthesize_arabic_tts_part_subprocess(part_text: str, part_path: str, work_dir: str):
    """Run tts_arabic in a fresh Python process for each small chunk.
    This prevents ONNXRuntime memory buildup/bad_alloc on long Arabic answers.
    """
    os.makedirs(work_dir, exist_ok=True)
    txt_path = os.path.join(work_dir, f"tts_part_{uuid.uuid4().hex}.txt")
    helper_path = os.path.join(work_dir, f"tts_helper_{uuid.uuid4().hex}.py")

    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(part_text)

    helper_code = '''
import sys
from tts_arabic import tts

text_path = sys.argv[1]
out_path = sys.argv[2]
speaker = int(sys.argv[3])
pace = float(sys.argv[4])
vowelizer = sys.argv[5]

with open(text_path, "r", encoding="utf-8") as f:
    text = f.read().strip()

tts(
    text,
    speaker=speaker,
    pace=pace,
    play=False,
    save_to=out_path,
    vowelizer=vowelizer,
)
'''
    with open(helper_path, "w", encoding="utf-8") as f:
        f.write(helper_code)

    try:
        proc = subprocess.run(
            [
                sys.executable,
                helper_path,
                txt_path,
                part_path,
                str(TTS_ARABIC_SPEAKER),
                str(TTS_ARABIC_PACE),
                TTS_ARABIC_VOWELIZER,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
        stdout = proc.stdout.decode("utf-8", errors="replace")
        stderr = proc.stderr.decode("utf-8", errors="replace")
        if proc.returncode != 0:
            raise RuntimeError((stderr or stdout or "tts_arabic subprocess failed")[-1800:])
        if not os.path.exists(part_path) or os.path.getsize(part_path) < 10000:
            size = os.path.getsize(part_path) if os.path.exists(part_path) else 0
            raise RuntimeError(f"tts_arabic subprocess produced invalid WAV. size={size}. {(stderr or stdout)[-800:]}")
    finally:
        for tmp in (txt_path, helper_path):
            try:
                if os.path.exists(tmp):
                    os.remove(tmp)
            except Exception:
                pass


def synthesize_tts(text: str):
    """
    Convert answer text to WAV.

    English:
      Piper Lessac voice.

    Arabic:
      tts_arabic (nipponjo) speaker=3 by default. This is the better Arabic voice you tested.
      If tts_arabic is unavailable or fails, it automatically falls back to your working Piper Arabic voice.
    """
    text = safe_tts_text(text)
    if not text:
        return None, None, "empty TTS text"

    arabic = is_arabic(text)
    out_dir = os.path.abspath(TTS_OUTPUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    fname = f"answer_{int(time.time())}_{uuid.uuid4().hex[:8]}.wav"
    out_path = os.path.join(out_dir, fname)

    # Preferred Arabic engine: nipponjo/tts_arabic
    if arabic and ARABIC_TTS_ENGINE == "tts_arabic":
        part_paths = []
        try:
            # Long Arabic answers can crash ONNXRuntime if synthesized in one call.
            # This version splits into small chunks AND runs each chunk in a fresh Python
            # process so memory is released between chunks.
            parts = split_tts_text(text, max_chars=260)
            if not parts:
                parts = [text]

            for i, part in enumerate(parts, 1):
                part_path = os.path.join(out_dir, f"answer_part_{int(time.time())}_{uuid.uuid4().hex[:8]}_{i}.wav")
                synthesize_arabic_tts_part_subprocess(part, part_path, out_dir)
                part_paths.append(part_path)

            if len(part_paths) == 1:
                try:
                    os.replace(part_paths[0], out_path)
                    part_paths = []
                except Exception:
                    concat_wavs(part_paths, out_path)
            else:
                concat_wavs(part_paths, out_path)

            if os.path.exists(out_path) and os.path.getsize(out_path) > 10000:
                for part_path in part_paths:
                    try:
                        os.remove(part_path)
                    except Exception:
                        pass
                meta = {
                    "filename": fname,
                    "size_bytes": os.path.getsize(out_path),
                    "voice": f"tts_arabic_speaker_{TTS_ARABIC_SPEAKER}",
                    "engine": "tts_arabic_subprocess_chunked",
                    "tts_parts": len(parts),
                }
                return f"/tts_outputs/{fname}", meta, None

            err_size = os.path.getsize(out_path) if os.path.exists(out_path) else 0
            arabic_err = f"tts_arabic chunked output invalid. size={err_size}. Falling back to Piper Arabic."
        except Exception as e:
            arabic_err = f"tts_arabic chunked failed: {e}. Falling back to Piper Arabic."
        finally:
            for part_path in part_paths:
                try:
                    if os.path.exists(part_path):
                        os.remove(part_path)
                except Exception:
                    pass
    else:
        arabic_err = None

    # Fallback / English engine: Piper through UTF-8 stdin.
    piper_exe = os.path.abspath(PIPER_EXE)
    piper_voice = os.path.abspath(PIPER_VOICE_AR if arabic else PIPER_VOICE)

    if not os.path.exists(piper_exe):
        return None, None, f"Piper exe not found: {piper_exe}"
    if not piper_voice or not os.path.exists(piper_voice):
        if arabic and arabic_err:
            return None, None, arabic_err + " Also Arabic Piper voice not found: " + piper_voice
        return None, None, (
            "Arabic TTS voice model not found. Expected: " + piper_voice
            if arabic else f"English Piper voice model not found: {piper_voice}"
        )

    cmd = [piper_exe, "-m", piper_voice, "-f", out_path]

    try:
        proc = subprocess.run(
            cmd,
            input=(text + "\n").encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )

        stdout = proc.stdout.decode("utf-8", errors="replace")
        stderr = proc.stderr.decode("utf-8", errors="replace")

        if proc.returncode != 0:
            err = (stderr or stdout or "Piper failed").strip()
            if arabic_err:
                err = arabic_err + " | Piper fallback error: " + err
            return None, None, err[-1800:]

        if not os.path.exists(out_path) or os.path.getsize(out_path) < 10000:
            err = (stderr or stdout or "Piper created an empty/invalid WAV file.").strip()
            msg = f"Piper output invalid. size={os.path.getsize(out_path) if os.path.exists(out_path) else 0}. " + err[-1200:]
            if arabic_err:
                msg = arabic_err + " | " + msg
            return None, None, msg

        meta = {
            "filename": fname,
            "size_bytes": os.path.getsize(out_path),
            "voice": "arabic_male_kareem_fallback" if arabic else "english_lessac",
            "engine": "piper",
        }
        return f"/tts_outputs/{fname}", meta, None
    except Exception as e:
        return None, None, str(e)

# ── Flask routes ──────────────────────────────────────────────────────────────

@app.after_request
def cors(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    resp.headers["Access-Control-Allow-Methods"] = "POST,GET,OPTIONS"
    return resp


@app.route("/ask", methods=["OPTIONS"])
@app.route("/v", methods=["OPTIONS"])
@app.route("/voice", methods=["OPTIONS"])
@app.route("/health", methods=["OPTIONS"])
def options():
    return Response(status=200)




@app.route("/")
@app.route("/chat_voice_ar_ready.html")
@app.route("/chat_voice_final_FIXED2.html")
@app.route("/chat_voice_final_fixed.html")
@app.route("/chat_voice_full.html")
@app.route("/chat_voice_whisper_final.html")
def home():
    """Open the full voice chat UI from localhost, so microphone and audio playback work correctly."""
    here = os.path.dirname(os.path.abspath(__file__)) or "."
    for name in ["chat_voice_rescate_TTS_ARABIC_FINAL.html", "chat_voice_rescate_AR_MALE_PIPER.html", "chat_voice_rescate_ar_female.html", "chat_voice_ar_ready.html", "chat_voice_final_FIXED2.html", "chat_voice_final_fixed.html", "chat_voice_full.html", "chat_voice_whisper_final.html", "chat_voice_ready.html"]:
        if os.path.exists(os.path.join(here, name)):
            return send_from_directory(here, name)
    return "Place chat_voice_full.html in the same folder as this server, then open http://localhost:8081/", 404


@app.route("/tts_audio/<path:filename>")
def tts_audio(filename):
    return send_from_directory(os.path.abspath(TTS_OUTPUT_DIR), filename, mimetype="audio/wav")

@app.route("/tts_outputs/<path:filename>")
def tts_outputs(filename):
    """Serve generated Piper WAV files for browser playback."""
    return send_from_directory(os.path.abspath(TTS_OUTPUT_DIR), filename, mimetype="audio/wav")


@app.route("/tts", methods=["GET", "POST"])
def tts():
    """Create TTS audio with Piper.
    GET /tts?text=hello returns WAV directly for testing.
    POST JSON {"text":"..."} returns JSON {tts_url,...} for the chat UI.
    POST /tts?raw=1 returns WAV directly.
    """
    try:
        if request.method == "GET":
            text = (request.args.get("text") or "").strip()
            raw = True
        else:
            data = request.get_json(force=True, silent=True) or {}
            text = (data.get("text") or "").strip()
            raw = request.args.get("raw") == "1"
        if not text:
            return jsonify({"error": "empty text"}), 400

        url, meta, err = synthesize_tts(text)
        if err:
            return jsonify({"error": err}), 500

        wav_path = os.path.join(os.path.abspath(TTS_OUTPUT_DIR), meta["filename"])
        if raw:
            return send_file(wav_path, mimetype="audio/wav", as_attachment=False, download_name=meta["filename"])
        return jsonify({"tts_url": url, "tts": meta})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/v", methods=["POST"])
@app.route("/voice", methods=["POST"])
def voice():
    """
    Voice endpoint using the stable production pipeline:
    mic upload -> faster-whisper STT -> either transcript only or normal RAG answer.
    Modes:
      debug      = only save uploaded file and return metadata
      transcribe = return Whisper transcript only
      answer     = transcribe, retrieve chunks, call llama.cpp text model, return medical answer
    """
    mode = (request.form.get("mode") or "transcribe").strip().lower()
    if mode not in {"debug", "transcribe", "answer"}:
        mode = "transcribe"

    voice_lang = (request.form.get("lang") or WHISPER_LANGUAGE or "auto").strip().lower()
    if voice_lang not in {"auto", "en", "ar"}:
        voice_lang = "auto"
    whisper_language = None if voice_lang == "auto" else voice_lang

    max_tokens  = int(request.form.get("max_tokens", DEFAULT_MAX_TOKENS))
    temperature = float(request.form.get("temperature", DEFAULT_TEMPERATURE))
    top_k       = int(request.form.get("top_k", DEFAULT_TOP_K))
    enable_tts  = (request.form.get("tts", "1") not in {"0", "false", "False", "no", "NO"})

    if "audio" not in request.files:
        return jsonify({"error": "No audio file received. Field name must be 'audio'."}), 400

    audio = request.files["audio"]
    if not audio.filename:
        return jsonify({"error": "Empty audio filename."}), 400

    os.makedirs(AUDIO_UPLOAD_DIR, exist_ok=True)
    safe_ext = os.path.splitext(audio.filename)[1].lower() or ".webm"
    if safe_ext not in {".wav", ".webm", ".ogg", ".mp3", ".m4a", ".mp4"}:
        safe_ext = ".webm"

    fname = f"voice_{int(time.time())}_{os.getpid()}{safe_ext}"
    path = os.path.join(AUDIO_UPLOAD_DIR, fname)
    audio.save(path)

    mime = audio.mimetype or mimetypes.guess_type(path)[0] or "application/octet-stream"
    meta = audio_metadata(path, mime)

    print(f"\n🎤 Voice upload: {fname} | mode={mode} | lang={voice_lang} | {meta.get('size_bytes',0)} bytes | mime={mime}")

    if mode == "debug":
        return jsonify({
            "message": "Voice upload OK. The backend received and saved your audio file correctly.",
            "saved_file": path,
            "audio": meta,
            "trace": "Microphone → browser recorder → multipart upload → Flask /voice endpoint: OK",
            "chunks": [],
        })

    # 1) Speech-to-text using faster-whisper. FFmpeg must be installed and visible in PATH.
    try:
        segments, info = whisper_model.transcribe(path, language=whisper_language, beam_size=5)
        transcript = " ".join(seg.text.strip() for seg in segments).strip()
    except Exception as e:
        return jsonify({
            "error": f"Whisper transcription failed: {e}",
            "saved_file": path,
            "audio": meta,
            "hint": "Make sure faster-whisper is installed and ffmpeg -version works in this terminal.",
        }), 500

    if not transcript:
        return jsonify({
            "error": "Could not understand audio. Try speaking louder/closer or record a longer sentence.",
            "saved_file": path,
            "audio": meta,
            "chunks": [],
        }), 400

    print(f"   📝 Transcript: {transcript}")

    if mode == "transcribe":
        return jsonify({
            "transcript": transcript,
            "answer": transcript,
            "audio": meta,
            "thinking": f"Whisper transcription OK.\ntranscript = {transcript}",
            "chunks": [],
            "tokens": {"prompt": 0, "completion": est_tok(transcript), "total": est_tok(transcript)},
        })

    # 2) Answer mode: use transcript as a normal RAG question.
    if not check_llama_alive():
        return jsonify({
            "error": (
                "Voice transcription worked, but llama.cpp server is not running on port 8080.\n\n"
                "Start it with:\n"
                "  cd D:\\llama.cpp\n"
                "  .\\llama-server.exe -m \"D:\\llama.cpp\\google_gemma-4-E2B-it-IQ2_M.gguf\" --port 8080 --ctx-size 4096 --threads 6"
            ),
            "transcript": transcript,
            "saved_file": path,
            "audio": meta,
            "chunks": [],
        }), 503

    chunks = search(transcript, top_k)
    prompt = build_prompt(transcript, chunks)
    trace = build_trace(transcript, chunks)

    try:
        answer, model_thinking, p_tok, c_tok = call_llama(prompt, max_tokens, temperature)
    except urllib.error.URLError as e:
        return jsonify({"error": f"Cannot reach llama.cpp: {e}", "transcript": transcript}), 503
    except Exception as e:
        return jsonify({"error": str(e), "transcript": transcript}), 500

    visible_thinking = (
        f"Voice transcript:\n{transcript}\n\n" +
        (model_thinking.strip() if model_thinking.strip() else trace)
    )

    tts_url, tts_meta, tts_error = (None, None, None)
    if enable_tts:
        tts_url, tts_meta, tts_error = synthesize_tts(answer)
        if tts_error:
            print(f"   ⚠ TTS error: {tts_error}")

    return jsonify({
        "answer": answer,
        "transcript": transcript,
        "audio": meta,
        "thinking": visible_thinking,
        "chunks": chunks,
        "lang": "arabic" if is_arabic(transcript) else "english",
        "tokens": {"prompt": p_tok, "completion": c_tok, "total": p_tok + c_tok},
        "tts_url": tts_url,
        "tts": tts_meta,
        "tts_error": tts_error,
    })

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
        "gemma_audio_configured": bool(GEMMA_AUDIO_CHAT_URL),
        "piper_ready": os.path.exists(os.path.abspath(PIPER_EXE)) and os.path.exists(os.path.abspath(PIPER_VOICE)),
        "arabic_tts_ready": bool(PIPER_VOICE_AR) and os.path.exists(os.path.abspath(PIPER_VOICE_AR)),
        "whisper_model": WHISPER_MODEL_NAME,
        "whisper_language": WHISPER_LANGUAGE,
    })


@app.route("/ask", methods=["POST"])
def ask():
    data = request.get_json(force=True)
    question    = data.get("question", "").strip()
    max_tokens  = int(data.get("max_tokens", DEFAULT_MAX_TOKENS))
    temperature = float(data.get("temperature", DEFAULT_TEMPERATURE))
    top_k       = int(data.get("top_k", DEFAULT_TOP_K))
    enable_tts  = bool(data.get("tts", ENABLE_TTS_DEFAULT))

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

    tts_url, tts_meta, tts_error = (None, None, None)
    if enable_tts:
        tts_url, tts_meta, tts_error = synthesize_tts(answer)
        if tts_error:
            print(f"   ⚠ TTS error: {tts_error}")

    return jsonify({
        "answer":   answer,
        "thinking": visible_thinking,
        "chunks":   chunks,
        "lang":     "arabic" if is_arabic(question) else "english",
        "tokens":   {"prompt": p_tok, "completion": c_tok, "total": p_tok + c_tok},
        "tts_url":  tts_url,
        "tts":      tts_meta,
        "tts_error": tts_error,
    })


if __name__ == "__main__":
    print("\n" + "═" * 55)
    print("  🏥  Grounded RAG Server — port", PORT)
    print("═" * 55)
    load()
    print(f"\n  Llama server expected at : {LLAMA_URL}")
    print(f"  Open browser at          : http://localhost:{PORT}")
    print(f"  Voice uploads folder     : {AUDIO_UPLOAD_DIR}")
    print(f"  Voice STT model          : {WHISPER_MODEL_NAME} ({WHISPER_DEVICE}/{WHISPER_COMPUTE_TYPE})")
    print(f"  Whisper language         : {WHISPER_LANGUAGE} (auto/en/ar)")
    print(f"  Piper exe                : {os.path.abspath(PIPER_EXE)}")
    print(f"  Piper voice EN           : {os.path.abspath(PIPER_VOICE)}")
    print(f"  Piper voice AR           : {os.path.abspath(PIPER_VOICE_AR) if PIPER_VOICE_AR else 'not configured'}")
    print(f"  TTS output folder        : {os.path.abspath(TTS_OUTPUT_DIR)}")
    print(f"  Default max_tokens       : {DEFAULT_MAX_TOKENS}  (lower = faster)")
    print("═" * 55 + "\n")
    app.run(host="0.0.0.0", port=PORT, debug=False)