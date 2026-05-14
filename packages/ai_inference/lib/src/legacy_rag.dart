import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LegacyRag {
  static const String systemPromptEn = """You are Rescate, an intelligent offline medical emergency and survival assistant designed for disaster zones, refugee camps, remote medicine, and low-resource environments.

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

The response should resemble a high-quality medical educational explanation rather than a chatbot response.""";
  static const String systemPromptAr = """أنت Rescate، مساعد طبي ذكي يعمل بدون إنترنت ومصمم لحالات الطوارئ والكوارث والمخيمات والمناطق ذات الموارد المحدودة.

مهمتك هي تقديم إجابات طبية مفصلة وهادئة ومبنية فقط على المعلومات الطبية الموجودة في السياق المرفق.

أسلوب الكتابة مهم جدًا.

يجب أن تبدو الإجابة وكأن طبيبًا أو مُثقفًا طبيًا يشرح الحالة بهدوء وبأسلوب مترابط خطوة بخطوة.

استخدم عبارات انتقالية بشكل طبيعي أثناء الشرح مثل:
- \"أولًا،\"
- \"في هذه الحالة،\"
- \"من المهم أن نفهم أن...\"
- \"مع تطور الحالة...\"
- \"نقطة مهمة أخرى هي...\"
- \"على سبيل المثال،\"
- \"بسبب ذلك...\"
- \"في الحالات الشديدة...\"
- \"في النهاية،\"

يجب أن تكون الإجابة بشرية وطبيعية وشرحها مترابط، وليست قصيرة أو آلية أو مجرد نقاط منفصلة.

القواعد:
- استخدم فقط المعلومات الموجودة في السياق الطبي المرفق.
- لا تخترع أي معلومات طبية.
- إذا لم تكن المعلومة متوفرة بوضوح، قل:
  \"هذه المعلومة غير متوفرة في المستندات المتاحة.
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

يجب أن تبدو الإجابة كشرح طبي واقعي ومترابط وغني بالمعلومات.""";

  static const Map<String, List<String>> arEnMap = {"حرق": ["burn", "burns", "burning"], "حروق": ["burn", "burns", "burning"], "لسعة": ["burn", "skin injury"], "حار": ["burn", "heat injury", "hot"], "نار": ["burn", "flame burn", "fire"], "لهب": ["flame burn", "burn", "fire"], "سخن": ["heat", "hot", "burn"], "ساخن": ["heat", "hot", "burn"], "حرارة": ["fever", "temperature", "heat"], "سخونية": ["fever", "temperature", "heat"], "تبريد": ["cool", "cooling", "burn care"], "برد": ["cold", "hypothermia"], "ثلج": ["ice", "cold", "burn cooling"], "انفجار": ["explosion", "blast", "blast injury", "trauma"], "تفجير": ["explosion", "blast"], "دخان": ["smoke", "inhalation", "airway"], "استنشاق": ["inhalation", "airway", "breathing"], "اختناق": ["airway", "breathing", "choking"], "تنفس": ["breathing", "respiratory", "airway", "inhalation"], "هواء": ["airway", "breathing", "oxygen", "inhalation"], "أكسجين": ["oxygen", "airway", "breathing"], "اكسجين": ["oxygen", "airway", "breathing"], "فوسفور": ["phosphorus", "white phosphorus", "chemical burn"], "فسفور": ["phosphorus", "white phosphorus", "chemical burn"], "ابيض": ["white phosphorus", "chemical burn"], "أبيض": ["white phosphorus", "chemical burn"], "كيميائي": ["chemical burn", "chemical"], "مواد": ["chemical", "exposure", "burn"], "حمض": ["acid", "corrosive", "chemical burn"], "قلوي": ["alkali", "corrosive", "chemical burn"], "كهربائي": ["electrical burn", "electrical"], "كهربا": ["electrical", "electrical burn", "shock"], "صعق": ["electrical burn", "electrical", "shock"], "تيار": ["electrical", "current", "shock"], "مياه": ["water", "fluid", "hydration"], "ماء": ["water", "fluid", "hydration"], "درجة": ["degree", "grade", "classification"], "درجه": ["degree", "grade", "classification"], "أولى": ["first degree", "superficial burn"], "اولى": ["first degree", "superficial burn"], "ثانية": ["second degree", "partial thickness burn"], "ثانيه": ["second degree", "partial thickness burn"], "ثالثة": ["third degree", "full thickness burn"], "ثالثه": ["third degree", "full thickness burn"], "سطحي": ["superficial burn", "first degree"], "سطحية": ["superficial burn", "superficial"], "جزئي": ["partial thickness burn", "second degree"], "عميق": ["deep partial thickness", "deep burn"], "كامل": ["full thickness", "third degree"], "فقاعات": ["blisters", "second degree burn"], "فقاعة": ["blister", "second degree burn"], "بثور": ["blisters", "burn"], "جلد": ["skin", "dermis", "epidermis"], "ابيضت": ["white", "full thickness burn"], "اسود": ["charred", "black", "full thickness burn"], "متفحم": ["charred", "full thickness burn"], "جرح": ["wound", "injury", "laceration"], "جروح": ["wound", "injury", "laceration"], "قطع": ["cut", "laceration", "wound"], "طعن": ["penetrating wound", "stab wound", "injury"], "نزيف": ["bleeding", "hemorrhage"], "ينزف": ["bleeding", "hemorrhage"], "دم": ["blood", "bleeding", "hemorrhage"], "شظية": ["shrapnel", "fragment", "blast injury"], "شظايا": ["shrapnel", "fragment", "blast injury"], "رصاص": ["bullet", "gunshot", "gunshot wound"], "طلقة": ["gunshot", "bullet wound"], "إصابة": ["injury", "trauma", "wound"], "اصابة": ["injury", "trauma", "wound"], "صدمة": ["shock", "trauma", "injury"], "صدمه": ["shock", "trauma", "injury"], "رض": ["trauma", "injury", "blunt trauma"], "كدمة": ["bruise", "contusion", "injury"], "كسر": ["fracture", "broken bone"], "كسور": ["fracture", "broken bone"], "عظم": ["bone", "fracture", "orthopedic"], "عظام": ["bone", "fracture", "orthopedic"], "خلع": ["dislocation", "joint injury"], "التواء": ["sprain", "strain", "musculoskeletal"], "بتر": ["amputation", "traumatic amputation"], "سحق": ["crush injury", "collapse", "trauma"], "انهيار": ["collapse", "building collapse", "crush injury"], "تورم": ["swelling", "edema", "injury"], "ورم": ["swelling", "edema"], "هوائي": ["airway", "breathing"], "تنفسه": ["breathing", "respiratory"], "يتنفس": ["breathing", "respiratory"], "نفس": ["breathing", "respiratory"], "لهاث": ["shortness of breath", "respiratory distress"], "نهجان": ["shortness of breath", "breathing difficulty"], "يزرق": ["blue lips", "cyanosis", "low oxygen"], "ازرق": ["cyanosis", "low oxygen"], "ازرقاق": ["cyanosis", "low oxygen"], "شرق": ["choking", "airway obstruction"], "بلع": ["ingestion", "swallowing", "poisoning"], "انسداد": ["obstruction", "bowel obstruction", "airway"], "انعاش": ["CPR", "resuscitation"], "إنعاش": ["CPR", "resuscitation"], "قلب": ["heart", "cardiac", "pulse"], "نبض": ["pulse", "heartbeat", "cardiac"], "تنفس صناعي": ["rescue breaths", "resuscitation", "CPR"], "ضغطات": ["chest compressions", "CPR"], "صدر": ["chest", "thoracic", "lung"], "رئة": ["lung", "breathing", "respiratory"], "رئه": ["lung", "breathing", "respiratory"], "ولادة": ["childbirth", "delivery", "labor"], "ولاده": ["childbirth", "delivery", "labor"], "طلق": ["labor", "delivery", "contractions"], "حامل": ["pregnancy", "pregnant"], "حمل": ["pregnancy", "pregnant"], "نفاس": ["postpartum", "after birth"], "بعد الولادة": ["postpartum", "after delivery"], "بعد الولاده": ["postpartum", "after delivery"], "نزيف بعد الولادة": ["postpartum hemorrhage", "bleeding after birth"], "مشيمة": ["placenta", "retained placenta"], "مشيمه": ["placenta", "retained placenta"], "رحم": ["uterus", "uterine"], "تشنج": ["seizure", "eclampsia", "convulsion"], "تشنجات": ["seizure", "eclampsia", "convulsion"], "صرع": ["seizure", "epilepsy", "convulsion"], "مولود": ["newborn", "baby", "neonate"], "مواليد": ["newborn", "neonate"], "رضيع": ["infant", "baby", "newborn"], "طفل": ["child", "baby", "infant"], "بيبي": ["baby", "newborn", "infant"], "مبتسر": ["premature baby", "preterm", "newborn"], "خديج": ["premature baby", "preterm", "newborn"], "لا يرضع": ["not feeding", "newborn emergency", "sepsis"], "يرضع": ["feeding", "breastfeeding", "newborn"], "رضاعة": ["breastfeeding", "feeding"], "يبكي": ["crying", "newborn assessment"], "لا يبكي": ["newborn not breathing", "resuscitation", "newborn emergency"], "لا يتنفس": ["not breathing", "resuscitation", "airway"], "بردان": ["hypothermia", "too cold", "newborn hypothermia"], "بارد": ["cold", "hypothermia"], "حمى": ["fever", "infection", "temperature"], "حرارته": ["fever", "temperature", "hot"], "السره": ["umbilical cord", "cord infection", "newborn"], "سرة": ["umbilical cord", "cord infection", "newborn"], "سره": ["umbilical cord", "cord infection", "newborn"], "صديد": ["pus", "infection", "umbilical infection"], "يرقان": ["jaundice", "newborn infection"], "صفار": ["jaundice", "newborn"], "عدوى": ["infection", "sepsis"], "التهاب": ["infection", "inflammation"], "تلوث": ["contamination", "infection"], "قيح": ["pus", "infection"], "قشعريرة": ["chills", "infection", "fever"], "خمول": ["lethargy", "weakness", "newborn infection"], "ضعف": ["weakness", "fatigue"], "يرتجف": ["shivering", "cold", "fever"], "تعفن": ["sepsis", "infection"], "تسمم": ["poisoning", "toxic", "poison"], "جلطة": ["stroke", "clot", "thrombosis", "embolism"], "سكتة": ["stroke", "brain emergency"], "سكتة دماغية": ["stroke", "cerebral", "CVA"], "دماغ": ["brain", "cerebral", "stroke"], "دماغية": ["brain", "cerebral", "stroke"], "رأس": ["head", "brain", "head injury"], "راس": ["head", "brain", "head injury"], "دوخة": ["dizziness", "vertigo", "fainting"], "دوار": ["dizziness", "vertigo"], "إغماء": ["fainting", "unconscious", "collapse"], "اغماء": ["fainting", "unconscious", "collapse"], "مغمى": ["unconscious", "collapse"], "مغمي": ["unconscious", "collapse"], "تشوش": ["confusion", "altered mental status"], "ارتباك": ["confusion", "altered mental status"], "شلل": ["paralysis", "stroke", "neurologic deficit"], "خدر": ["numbness", "neurologic deficit"], "ألم": ["pain"], "الم": ["pain"], "وجع": ["pain"], "حارق": ["burning pain", "burn"], "بطن": ["abdomen", "abdominal", "stomach"], "معدة": ["stomach", "abdomen"], "ظهر": ["back", "spine", "back pain"], "رقبة": ["neck", "airway", "trauma"], "عين": ["eye", "ocular", "vision"], "اذن": ["ear", "hearing"], "أذن": ["ear", "hearing"], "يد": ["hand", "upper limb"], "رجل": ["leg", "lower limb"], "ساق": ["leg", "limb", "extremity"], "ذراع": ["arm", "upper limb", "extremity"], "علاج": ["treatment", "therapy", "management"], "تدبير": ["management", "treatment"], "تصرف": ["what to do", "management", "first aid"], "اعمل": ["what to do", "management", "first aid"], "أسعف": ["first aid", "emergency treatment"], "اسعف": ["first aid", "emergency treatment"], "إسعاف": ["first aid", "emergency", "treatment"], "اسعاف": ["first aid", "emergency", "treatment"], "ماذا": ["what", "management"], "شلون": ["what to do", "management"], "ازاي": ["what to do", "management"], "كيف": ["how", "management"], "سوائل": ["fluids", "resuscitation", "hydration"], "محلول": ["IV fluid", "resuscitation", "lactated ringer"], "رينجر": ["lactated ringer", "ringer lactate", "fluid resuscitation"], "تعويض": ["resuscitation", "fluids"], "جفاف": ["dehydration", "fluids", "hydration"], "ترطيب": ["hydration", "fluids"], "بول": ["urine output", "kidney", "resuscitation"], "تبول": ["urine output", "kidney"], "ابني": ["my baby", "child", "newborn", "infant"], "بنتي": ["my baby", "child", "infant"], "عيلي": ["my child", "baby", "infant"], "طفلي": ["my child", "baby", "infant"], "مراتي": ["wife", "mother", "postpartum"], "مرتي": ["wife", "mother", "postpartum"], "امي": ["mother", "adult patient"], "أمي": ["mother", "adult patient"], "سكري": ["diabetes", "diabetic", "blood sugar", "glucose"], "سكر": ["diabetes", "blood sugar", "glucose"], "سكرية": ["diabetes", "diabetic"], "انسولين": ["insulin", "diabetes"], "جلوكوز": ["glucose", "blood sugar", "hypoglycemia"], "هبوط سكر": ["hypoglycemia", "low blood sugar", "glucose"], "هبوط": ["hypoglycemia", "low blood sugar", "fainting"], "ارتفاع سكر": ["hyperglycemia", "high blood sugar", "DKA"], "كيتو": ["ketoacidosis", "DKA", "diabetes"], "حماض": ["ketoacidosis", "DKA", "acidosis"], "ضغط": ["blood pressure", "hypertension"], "ضغط الدم": ["blood pressure", "hypertension"], "ضغط عالي": ["hypertension", "high blood pressure"], "ارتفاع الضغط": ["hypertension", "high blood pressure"], "انخفاض الضغط": ["hypotension", "low blood pressure", "shock"], "قصور القلب": ["heart failure", "cardiac failure"], "فشل القلب": ["heart failure", "cardiac failure"], "وذمة": ["edema", "swelling", "heart failure"], "ربو": ["asthma", "bronchospasm", "breathing"], "ربو القصبات": ["asthma", "bronchospasm"], "نوبة صرع": ["seizure", "epilepsy", "status epilepticus"], "اختلاج": ["seizure", "convulsion"], "غدة درقية": ["thyroid", "hypothyroidism"], "خمول الغدة": ["hypothyroidism", "thyroid"], "غيبوبة": ["coma", "unconscious", "myxedema"], "غيبوبه": ["coma", "unconscious"], "افاقه": ["recovery", "regain consciousness"], "جلطة دماغية": ["stroke", "cerebral infarction"], "احتشاء": ["infarction", "stroke", "myocardial infarction"], "شلل نصف": ["hemiplegia", "stroke", "paralysis"], "وجه مائل": ["facial droop", "stroke", "FAST"], "يد ضعيفة": ["arm weakness", "stroke", "FAST"], "كلام مش واضح": ["slurred speech", "stroke", "FAST"], "صداع شديد": ["severe headache", "meningitis", "stroke", "subarachnoid"], "صداع": ["headache", "meningitis", "stroke"], "رقبة متصلبة": ["neck stiffness", "meningitis"], "تيبس الرقبة": ["neck stiffness", "meningitis"], "تصلب الرقبة": ["neck stiffness", "meningitis"], "حساسية للضوء": ["photophobia", "meningitis"], "طفح": ["rash", "meningococcal", "meningitis"], "طفح جلدي": ["rash", "meningococcal", "petechiae"], "بقع حمراء": ["petechiae", "meningococcal", "rash"], "التهاب السحايا": ["meningitis", "meningococcal"], "سحايا": ["meningitis"], "ارتجاج": ["concussion", "head injury", "TBI"], "ضربة رأس": ["head injury", "concussion", "TBI"], "اصابة الرأس": ["head injury", "TBI", "concussion"], "مقياس جلاسكو": ["GCS", "glasgow coma scale", "head injury"], "ضعف في المخ": ["brain injury", "stroke", "head injury"], "نزيف مخي": ["intracranial hemorrhage", "brain bleed", "head injury"], "عين مختلفة": ["unequal pupils", "herniation", "head injury"], "حدقة": ["pupil", "eye", "head injury"], "نزيف شديد": ["hemorrhage", "hypovolemic shock", "blood loss"], "صدمة دموية": ["hypovolemic shock", "hemorrhage", "blood loss"], "نزف": ["bleeding", "hemorrhage", "blood loss"], "ضاغط": ["tourniquet", "hemorrhage control"], "حزام الضغط": ["tourniquet", "pressure", "hemorrhage"], "ضغط مباشر": ["direct pressure", "wound", "bleeding"], "توتر": ["stress", "anxiety", "acute stress reaction"], "صدمة نفسية": ["trauma", "PTSD", "psychological"], "اضطراب ما بعد الصدمة": ["PTSD", "trauma", "mental health"], "كآبة": ["depression", "grief", "mental health"], "اكتئاب": ["depression", "mental health"], "انتحار": ["suicide", "suicidal", "mental health"], "يريد ان يموت": ["suicidal ideation", "suicide risk"], "حزن": ["grief", "bereavement", "mental health"], "فقدان": ["loss", "grief", "bereavement"], "هلوسة": ["hallucination", "psychosis", "mental health"], "جنون": ["psychosis", "mental health"], "ذهان": ["psychosis", "delusion"], "وسواس": ["anxiety", "OCD", "mental health"], "اسعافات نفسية": ["psychological first aid", "PFA", "mental health"], "سم": ["poison", "poisoning", "toxic"], "مبيد": ["pesticide", "organophosphate", "poisoning"], "مبيدات": ["pesticide", "organophosphate", "poisoning"], "مبيد حشري": ["insecticide", "organophosphate", "SLUDGE"], "اعصاب": ["nerve agent", "organophosphate", "chemical weapon"], "غاز اعصاب": ["nerve agent", "sarin", "chemical weapon"], "سارين": ["sarin", "nerve agent", "organophosphate"], "اوكسيد الكربون": ["carbon monoxide", "CO poisoning"], "غاز الكربون": ["carbon monoxide", "CO poisoning"], "احتراق": ["combustion", "carbon monoxide", "inhalation"], "مولد كهرباء": ["generator", "carbon monoxide", "CO poisoning"], "لدغة": ["bite", "snakebite", "envenomation"], "لسعة ثعبان": ["snakebite", "venom", "envenomation"], "ثعبان": ["snake", "snakebite", "venom"], "افعى": ["viper", "snakebite", "venom"], "عقرب": ["scorpion", "envenomation", "sting"], "حامض": ["acid", "corrosive"], "ابتلع": ["ingested", "swallowed", "poisoning"], "كحول": ["alcohol", "poisoning"], "فحم نشط": ["activated charcoal", "poisoning treatment"], "يتقيأ": ["vomiting", "poisoning", "nausea"], "قيء": ["vomiting", "poisoning", "nausea"], "غثيان": ["nausea", "vomiting", "poisoning"], "بطن حاد": ["acute abdomen", "peritonitis", "surgical emergency"], "زائدة": ["appendicitis", "acute abdomen"], "انتان": ["peritonitis", "infection", "acute abdomen"], "التهاب الزائدة": ["appendicitis", "acute abdomen"], "التهاب الصفاق": ["peritonitis", "acute abdomen"], "انسداد معوي": ["intestinal obstruction", "bowel obstruction"], "حمل خارج الرحم": ["ectopic pregnancy", "acute abdomen"], "اسهال": ["diarrhea", "dehydration"], "اسهاله": ["diarrhea", "dehydration"], "اسهالات": ["diarrhea", "dehydration", "cholera"], "كوليرا": ["cholera", "diarrhea", "dehydration"], "محلول الإماهة": ["ORS", "oral rehydration", "dehydration"], "محلول إماهة": ["ORS", "rehydration", "dehydration"], "جفاف شديد": ["severe dehydration", "IV fluids", "shock"], "خلع كتف": ["shoulder dislocation", "dislocation"], "ألم الظهر": ["back pain", "spine", "lumbar"], "نخاع شوكي": ["spinal cord", "spine", "cauda equina"], "ذيل الفرس": ["cauda equina", "spine", "emergency"], "ذبحة": ["angina", "chest pain", "cardiac"], "احتشاء قلب": ["myocardial infarction", "heart attack", "chest pain"], "نوبة قلبية": ["heart attack", "myocardial infarction", "cardiac arrest"], "توقف القلب": ["cardiac arrest", "CPR", "resuscitation"], "استرواح": ["pneumothorax", "chest", "breathing"], "استرواح صدري": ["pneumothorax", "tension pneumothorax"], "ضغط مجوف": ["tension pneumothorax", "needle decompression"], "جرح الصدر": ["chest wound", "open chest wound", "sucking chest wound"], "جروح الصدر": ["chest wound", "penetrating chest", "pneumothorax"], "كسر الضلوع": ["rib fracture", "chest trauma", "flail chest"], "ضلوع": ["ribs", "rib fracture", "chest"], "التهاب رئوي": ["pneumonia", "lung infection", "respiratory"], "التهاب الرئة": ["pneumonia", "lung infection"], "ذات الرئة": ["pneumonia", "lung infection"], "جبيرة": ["splint", "immobilization", "fracture"], "جبس": ["cast", "plaster", "fracture"], "كسر مفتوح": ["open fracture", "compound fracture"], "كسر مركب": ["compound fracture", "open fracture"], "ورك": ["hip", "hip fracture", "pelvis"], "حوض": ["pelvis", "pelvic fracture", "hemorrhage"], "فخذ": ["femur", "thigh", "femur fracture"], "كعب": ["ankle", "ankle fracture", "sprain"], "متلازمة الحجرة": ["compartment syndrome", "fracture complication"], "انسداد وعاء": ["vascular compromise", "ischemia", "compartment"]};
  static const Map<String, List<String>> enExpansions = {"baby": ["baby", "infant", "newborn", "neonate", "child"], "infant": ["infant", "baby", "newborn", "neonate"], "newborn": ["newborn", "neonate", "baby", "infant"], "fever": ["fever", "high temperature", "temperature", "hot", "febrile"], "hypothermia": ["hypothermia", "cold", "low temperature", "warming", "warm", "skin-to-skin"], "cold": ["cold", "hypothermia", "low temperature", "warming", "warm"], "bleeding": ["bleeding", "hemorrhage", "blood loss", "haemorrhage"], "burn": ["burn", "burns", "burning", "thermal injury"], "choking": ["choking", "airway", "obstruction", "not breathing"], "fracture": ["fracture", "broken bone", "immobilization", "splint"], "shock": ["shock", "hemorrhage", "hypovolemic", "blood loss", "hypotension"], "wound": ["wound", "laceration", "injury", "bleeding", "hemorrhage"], "crush": ["crush injury", "compartment syndrome", "trauma"], "blast": ["blast injury", "explosion", "shrapnel", "trauma"], "dislocation": ["dislocation", "reduction", "joint injury"], "sprain": ["sprain", "strain", "RICE", "soft tissue"], "breathing": ["breathing", "respiratory", "airway", "breath"], "asthma": ["asthma", "bronchospasm", "wheeze", "inhaler", "salbutamol"], "pneumonia": ["pneumonia", "lung infection", "respiratory", "CURB-65"], "pneumothorax": ["pneumothorax", "chest", "tension pneumothorax", "needle decompression"], "chest": ["chest", "thoracic", "pneumothorax", "rib", "lung"], "stroke": ["stroke", "CVA", "FAST", "cerebral", "thrombolysis"], "seizure": ["seizure", "epilepsy", "convulsion", "status epilepticus"], "meningitis": ["meningitis", "meningococcal", "neck stiffness", "petechiae"], "headache": ["headache", "meningitis", "stroke", "subarachnoid"], "unconscious": ["unconscious", "loss of consciousness", "GCS", "coma"], "head": ["head injury", "TBI", "concussion", "GCS", "skull"], "diabetes": ["diabetes", "diabetic", "hypoglycemia", "DKA", "insulin"], "diabetic": ["diabetic", "diabetes", "hypoglycemia", "blood sugar"], "hypoglycemia": ["hypoglycemia", "low blood sugar", "glucose", "sugar"], "hypertension": ["hypertension", "blood pressure", "BP", "stroke"], "heart": ["heart", "cardiac", "heart failure", "pulmonary edema"], "epilepsy": ["epilepsy", "seizure", "convulsion", "status epilepticus"], "poison": ["poison", "poisoning", "toxic", "toxidrome"], "poisoning": ["poisoning", "toxic", "antidote", "activated charcoal"], "snakebite": ["snakebite", "venom", "envenomation", "antivenom"], "snake": ["snake", "snakebite", "venom", "antivenom"], "organophosphate": ["organophosphate", "pesticide", "SLUDGE", "nerve agent", "atropine"], "carbon": ["carbon monoxide", "CO poisoning", "smoke inhalation", "oxygen"], "corrosive": ["corrosive", "acid", "alkali", "chemical burn"], "diarrhea": ["diarrhea", "dehydration", "ORS", "rehydration"], "dehydration": ["dehydration", "ORS", "rehydration", "fluids"], "abdomen": ["abdomen", "acute abdomen", "peritonitis", "appendicitis"], "back": ["back pain", "spine", "lumbar", "cauda equina"], "suicide": ["suicide", "suicidal", "mental health", "crisis"], "ptsd": ["PTSD", "post-traumatic", "trauma", "mental health"], "psychosis": ["psychosis", "hallucination", "delusion", "mental health"], "grief": ["grief", "bereavement", "loss", "mental health"], "stress": ["stress", "acute stress reaction", "psychological first aid"]};

  static List<Map<String, dynamic>> _chunks = [];

  static Future<void> initialize() async {
    if (_chunks.isNotEmpty) return;
    try {
      final jsonString = await rootBundle.loadString('assets/chunks.json');
      final list = jsonDecode(jsonString) as List<dynamic>;
      _chunks = list.cast<Map<String, dynamic>>();
      for (var chunk in _chunks) {
        chunk['cn'] = (chunk['text'] as String).toLowerCase();
      }
      debugPrint('[LegacyRag] Loaded \${_chunks.length} chunks from assets.');
    } catch (e) {
      debugPrint('[LegacyRag] Failed to load chunks: \$e');
    }
  }

  static bool isArabic(String text) {
    final ar = RegExp(r'[؀-ۿ]').allMatches(text).length;
    final en = RegExp(r'[A-Za-z]').allMatches(text).length;
    return ar > en;
  }

  static String normalizeArabic(String text) {
    var t = text.trim().toLowerCase();
    t = t.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
    t = t.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    t = t.replaceAll('ى', 'ي').replaceAll('ة', 'ه');
    t = t.replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');
    t = t.replaceAll('ـ', '');
    t = t.replaceAll(RegExp(r'[^؀-ۿa-zA-Z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static List<String> _getEnglishTermsFromArabic(String question) {
    final qn = normalizeArabic(question);
    final words = qn.split(' ').where((w) => w.length >= 2).toList();
    final englishTerms = <String>[];
    
    final normalizedMap = <String, List<String>>{};
    for (var entry in arEnMap.entries) {
      normalizedMap[normalizeArabic(entry.key)] = entry.value;
    }
    
    for (var w in words) {
      for (var entry in normalizedMap.entries) {
        if (entry.key.contains(w) || w.contains(entry.key)) {
          englishTerms.addAll(entry.value);
        }
      }
    }
    return englishTerms.toSet().toList();
  }

  static List<String> _getEnglishTerms(String question) {
    var q = question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ');
    final stopWords = {"a","an","the","and","or","but","if","then","to","of","in","on","for","with","without","my","me","i","you","your","we","our","is","are","was","were","be","been","being","has","have","had","having","do","does","did","what","how","when","where","why","help","out","please","can","could","should","would","someone","person","patient","very","severe","serious","really","now","right","tell","need"};
    
    final words = q.split(' ').where((w) => w.length >= 3 && !stopWords.contains(w)).toList();
    final terms = <String>[];
    for (var w in words) {
      terms.add(w);
      if (enExpansions.containsKey(w)) {
        terms.addAll(enExpansions[w]!);
      }
    }
    return terms.toSet().toList();
  }

  static List<Map<String, dynamic>> search(String question, {int topK = 5}) {
    if (_chunks.isEmpty) return [];
    
    final isAr = isArabic(question);
    final termsToSearch = isAr ? _getEnglishTermsFromArabic(question) : _getEnglishTerms(question);
    
    final rawWords = (isAr ? normalizeArabic(question) : question.toLowerCase())
        .split(' ')
        .where((w) => w.length >= 3)
        .toList();
        
    final allSearchTerms = [...termsToSearch, ...rawWords].toSet().toList();
    
    final scored = <Map<String, dynamic>>[];
    for (var chunk in _chunks) {
      final text = chunk['text'] as String;
      final cn = chunk['cn'] as String;
      var score = 0;
      for (var w in allSearchTerms) {
        var count = 0;
        var idx = cn.indexOf(w);
        while (idx != -1) {
          count++;
          idx = cn.indexOf(w, idx + w.length);
        }
        score += count;
      }
      if (score > 0) {
        scored.add({
          'source': chunk['source'],
          'text': text,
          'score': score.toDouble(),
        });
      }
    }
    
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(topK).toList();
  }

  static String buildPrompt({required String question, required List<Map<String, dynamic>> chunks}) {
    final arabic = isArabic(question);
    final systemPrompt = arabic ? systemPromptAr : systemPromptEn;
    
    final noInfo = arabic ? "هذه المعلومة غير متوفرة في المحتوى الطبي المقدم." : "This information is not available in the provided documents.";
    final questionLabel = arabic ? "السؤال" : "QUESTION";
    final answerLabel = arabic ? "الإجابة بالعربية" : "ANSWER";
    
    String context;
    if (chunks.isEmpty) {
      context = "NO_RELEVANT_CONTEXT";
    } else {
      final compact = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        final c = chunks[i];
        var text = (c['text'] as String).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.length > 400) {
          text = text.substring(0, 400) + '...';
        }
        compact.add('[${i+1}] source=${c['source'] ?? 'unknown'} score=${c['score'] ?? '?'}\n$text');
      }
      context = compact.join('\n\n---\n\n');
    }
    
    final userMsg = arabic 
        ? "المرجع الطبي:\n$context\n\n$questionLabel: $question\n\nالتعليمات:\n- أجب بالعربية فقط باستخدام المعلومات الموجودة في المرجع أعلاه.\n- اذكر الخطوات العملية المحددة الموجودة في المرجع.\n- لا تكرر نفس الجملة أو نفس الفكرة مرتين.\n- إذا لم تكن المعلومات متوفرة اكتب: $noInfo\n\n$answerLabel:"
        : "MEDICAL REFERENCE:\n$context\n\n$questionLabel: $question\n\nInstructions:\n- Answer using ONLY the specific facts in the reference above.\n- State the concrete steps or signs mentioned in the reference.\n- Do NOT repeat the same sentence or idea twice.\n- If unavailable, write exactly: $noInfo\n\n$answerLabel:";

    return "<start_of_turn>system\n$systemPrompt<end_of_turn>\n<start_of_turn>user\n$userMsg<end_of_turn>\n<start_of_turn>model\n";
  }
}