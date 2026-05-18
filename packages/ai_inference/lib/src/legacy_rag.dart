import 'dart:collection';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class LegacyRag {
  static const String systemPromptEn = """You are Rescate, a calm field medic for war zones and refugee camps. Professional care may be unreachable.

EMERGENCY FIRST — if the user describes active danger right now (heavy bleeding, amputation, choking, unconscious, poisoning, labor): act immediately, no questions first. Give steps in order, short sentences, one action per sentence. Ask one thing only if the answer changes the next step.

NON-EMERGENCY — symptom or complaint: one brief empathetic clause, then ask the single most branching question — the one whose answer splits your thinking the most. Use plain-language analogies a non-medical person can answer. Then stop. Wait. Do not ask anything else yet. Once you know the symptom character, or if the diagnosis is already clear, ask once what supplies they have if it affects your advice. Then stop. Do not stack questions.

General medical question: short prose answer, conversational.

Always: natural prose, no bullets, no markdown, no headings. No greetings, no disclaimers, no "I am an AI", no "see a doctor". Match advice to available resources — improvise if needed. State warning signs when self-management may be failing. Use facts from the MEDICAL REFERENCE below; if missing, say so. Reply in the user's language.""";
  static const String systemPromptAr = """أنت Rescate، مسعف ميداني هادئ في مناطق الحرب والمخيمات حيث قد لا تتوفر صيدليات ولا أطباء. افرز كطبيب حقيقي قبل أن تنصح.

تحية ("مرحبا"): جملة واحدة قصيرة ودودة. لا شيء آخر.

سؤال طبي عام: فقرة قصيرة متدفقة بأسلوب محادثة.

عرض أو شكوى: لا تعالج بعد. جملة قصيرة متعاطفة، ثم سؤال أو سؤالان مركّزان تتغيّر نصيحتك بناءً على إجاباتهما. صُغهما بتشبيهات بسيطة يفهمها شخص بلا خلفية طبية (مثلاً "أقرب إلى خدش حاد مع كل رمشة، أم إلى جفاف يجعلك تريد إغلاق عينيك")؛ كل خيار يجب أن يقابل في ذهنك سبباً وعلاجاً مختلفَين. تجاوز الأسئلة إن كان المستخدم قد أعطى ما يكفي.

قبل أي توصية، اسأل مرة واحدة عمّا يملكه فعلاً (محلول، ماء نظيف، أو لا شيء). طابق النصيحة مع موارده: الرعاية القياسية إن توفرت، وإلا أفضل بديل ارتجالي يمكنك تبريره (ماء مغلي ومبرّد، قطعة قماش نظيفة، ظل، ضغط، وضعية). اذكر العلامات التي تعني فشل التدبير الذاتي.

طوارئ فعلية (مصاب، يختنق، ينزف، فاقد وعي، في طلق، مسموم): اترك الأسئلة. ابدأ فوراً بما يجب فعله بالترتيب، بجمل قصيرة يتبعها شخص خائف. اسأل عن تفصيل واحد فقط إن كان يعيقك.

دائماً: نثر طبيعي، بلا نقاط أو قوائم أو عناوين أو تنسيق. لا تحية، لا تلخيص للسؤال، لا إخلاء مسؤولية، لا "أنا ذكاء اصطناعي"، ولا "استشر طبيباً" أو "اطلب الإسعاف" — افترض أن الرعاية المهنية قد لا تكون متاحة. استخدم حقائق المرجع الطبي أدناه؛ إن نقصت معلومة، قل ذلك أو اطلبها. أجب بلغة المستخدم.""";

  static const Map<String, List<String>> arEnMap = {"حرق": ["burn", "burns", "burning"], "حروق": ["burn", "burns", "burning"], "لسعة": ["burn", "skin injury"], "حار": ["burn", "heat injury", "hot"], "نار": ["burn", "flame burn", "fire"], "لهب": ["flame burn", "burn", "fire"], "سخن": ["heat", "hot", "burn"], "ساخن": ["heat", "hot", "burn"], "حرارة": ["fever", "temperature", "heat"], "سخونية": ["fever", "temperature", "heat"], "تبريد": ["cool", "cooling", "burn care"], "برد": ["cold", "hypothermia"], "ثلج": ["ice", "cold", "burn cooling"], "انفجار": ["explosion", "blast", "blast injury", "trauma"], "تفجير": ["explosion", "blast"], "دخان": ["smoke", "inhalation", "airway"], "استنشاق": ["inhalation", "airway", "breathing"], "اختناق": ["airway", "breathing", "choking"], "تنفس": ["breathing", "respiratory", "airway", "inhalation"], "هواء": ["airway", "breathing", "oxygen", "inhalation"], "أكسجين": ["oxygen", "airway", "breathing"], "اكسجين": ["oxygen", "airway", "breathing"], "فوسفور": ["phosphorus", "white phosphorus", "chemical burn"], "فسفور": ["phosphorus", "white phosphorus", "chemical burn"], "ابيض": ["white phosphorus", "chemical burn"], "أبيض": ["white phosphorus", "chemical burn"], "كيميائي": ["chemical burn", "chemical"], "مواد": ["chemical", "exposure", "burn"], "حمض": ["acid", "corrosive", "chemical burn"], "قلوي": ["alkali", "corrosive", "chemical burn"], "كهربائي": ["electrical burn", "electrical"], "كهربا": ["electrical", "electrical burn", "shock"], "صعق": ["electrical burn", "electrical", "shock"], "تيار": ["electrical", "current", "shock"], "مياه": ["water", "fluid", "hydration"], "ماء": ["water", "fluid", "hydration"], "درجة": ["degree", "grade", "classification"], "درجه": ["degree", "grade", "classification"], "أولى": ["first degree", "superficial burn"], "اولى": ["first degree", "superficial burn"], "ثانية": ["second degree", "partial thickness burn"], "ثانيه": ["second degree", "partial thickness burn"], "ثالثة": ["third degree", "full thickness burn"], "ثالثه": ["third degree", "full thickness burn"], "سطحي": ["superficial burn", "first degree"], "سطحية": ["superficial burn", "superficial"], "جزئي": ["partial thickness burn", "second degree"], "عميق": ["deep partial thickness", "deep burn"], "كامل": ["full thickness", "third degree"], "فقاعات": ["blisters", "second degree burn"], "فقاعة": ["blister", "second degree burn"], "بثور": ["blisters", "burn"], "جلد": ["skin", "dermis", "epidermis"], "ابيضت": ["white", "full thickness burn"], "اسود": ["charred", "black", "full thickness burn"], "متفحم": ["charred", "full thickness burn"], "جرح": ["wound", "injury", "laceration"], "جروح": ["wound", "injury", "laceration"], "قطع": ["cut", "laceration", "wound"], "طعن": ["penetrating wound", "stab wound", "injury"], "نزيف": ["bleeding", "hemorrhage"], "ينزف": ["bleeding", "hemorrhage"], "دم": ["blood", "bleeding", "hemorrhage"], "شظية": ["shrapnel", "fragment", "blast injury"], "شظايا": ["shrapnel", "fragment", "blast injury"], "رصاص": ["bullet", "gunshot", "gunshot wound"], "طلقة": ["gunshot", "bullet wound"], "إصابة": ["injury", "trauma", "wound"], "اصابة": ["injury", "trauma", "wound"], "صدمة": ["shock", "trauma", "injury"], "صدمه": ["shock", "trauma", "injury"], "رض": ["trauma", "injury", "blunt trauma"], "كدمة": ["bruise", "contusion", "injury"], "كسر": ["fracture", "broken bone"], "كسور": ["fracture", "broken bone"], "عظم": ["bone", "fracture", "orthopedic"], "عظام": ["bone", "fracture", "orthopedic"], "خلع": ["dislocation", "joint injury"], "التواء": ["sprain", "strain", "musculoskeletal"], "بتر": ["amputation", "traumatic amputation"], "سحق": ["crush injury", "collapse", "trauma"], "انهيار": ["collapse", "building collapse", "crush injury"], "تورم": ["swelling", "edema", "injury"], "ورم": ["swelling", "edema"], "هوائي": ["airway", "breathing"], "تنفسه": ["breathing", "respiratory"], "يتنفس": ["breathing", "respiratory"], "نفس": ["breathing", "respiratory"], "لهاث": ["shortness of breath", "respiratory distress"], "نهجان": ["shortness of breath", "breathing difficulty"], "يزرق": ["blue lips", "cyanosis", "low oxygen"], "ازرق": ["cyanosis", "low oxygen"], "ازرقاق": ["cyanosis", "low oxygen"], "شرق": ["choking", "airway obstruction"], "بلع": ["ingestion", "swallowing", "poisoning"], "انسداد": ["obstruction", "bowel obstruction", "airway"], "انعاش": ["CPR", "resuscitation"], "إنعاش": ["CPR", "resuscitation"], "قلب": ["heart", "cardiac", "pulse"], "نبض": ["pulse", "heartbeat", "cardiac"], "تنفس صناعي": ["rescue breaths", "resuscitation", "CPR"], "ضغطات": ["chest compressions", "CPR"], "صدر": ["chest", "thoracic", "lung"], "رئة": ["lung", "breathing", "respiratory"], "رئه": ["lung", "breathing", "respiratory"], "ولادة": ["childbirth", "delivery", "labor"], "ولاده": ["childbirth", "delivery", "labor"], "طلق": ["labor", "delivery", "contractions"], "حامل": ["pregnancy", "pregnant"], "حمل": ["pregnancy", "pregnant"], "نفاس": ["postpartum", "after birth"], "بعد الولادة": ["postpartum", "after delivery"], "بعد الولاده": ["postpartum", "after delivery"], "نزيف بعد الولادة": ["postpartum hemorrhage", "bleeding after birth"], "مشيمة": ["placenta", "retained placenta"], "مشيمه": ["placenta", "retained placenta"], "رحم": ["uterus", "uterine"], "تشنج": ["seizure", "eclampsia", "convulsion"], "تشنجات": ["seizure", "eclampsia", "convulsion"], "صرع": ["seizure", "epilepsy", "convulsion"], "مولود": ["newborn", "baby", "neonate"], "مواليد": ["newborn", "neonate"], "رضيع": ["infant", "baby", "newborn"], "طفل": ["child", "baby", "infant"], "بيبي": ["baby", "newborn", "infant"], "مبتسر": ["premature baby", "preterm", "newborn"], "خديج": ["premature baby", "preterm", "newborn"], "لا يرضع": ["not feeding", "newborn emergency", "sepsis"], "يرضع": ["feeding", "breastfeeding", "newborn"], "رضاعة": ["breastfeeding", "feeding"], "يبكي": ["crying", "newborn assessment"], "لا يبكي": ["newborn not breathing", "resuscitation", "newborn emergency"], "لا يتنفس": ["not breathing", "resuscitation", "airway"], "بردان": ["hypothermia", "too cold", "newborn hypothermia"], "بارد": ["cold", "hypothermia"], "حمى": ["fever", "infection", "temperature"], "حرارته": ["fever", "temperature", "hot"], "السره": ["umbilical cord", "cord infection", "newborn"], "سرة": ["umbilical cord", "cord infection", "newborn"], "سره": ["umbilical cord", "cord infection", "newborn"], "صديد": ["pus", "infection", "umbilical infection"], "يرقان": ["jaundice", "newborn infection"], "صفار": ["jaundice", "newborn"], "عدوى": ["infection", "sepsis"], "التهاب": ["infection", "inflammation"], "تلوث": ["contamination", "infection"], "قيح": ["pus", "infection"], "قشعريرة": ["chills", "infection", "fever"], "خمول": ["lethargy", "weakness", "newborn infection"], "ضعف": ["weakness", "fatigue"], "يرتجف": ["shivering", "cold", "fever"], "تعفن": ["sepsis", "infection"], "تسمم": ["poisoning", "toxic", "poison"], "جلطة": ["stroke", "clot", "thrombosis", "embolism"], "سكتة": ["stroke", "brain emergency"], "سكتة دماغية": ["stroke", "cerebral", "CVA"], "دماغ": ["brain", "cerebral", "stroke"], "دماغية": ["brain", "cerebral", "stroke"], "رأس": ["head", "brain", "head injury"], "راس": ["head", "brain", "head injury"], "دوخة": ["dizziness", "vertigo", "fainting"], "دوار": ["dizziness", "vertigo"], "إغماء": ["fainting", "unconscious", "collapse"], "اغماء": ["fainting", "unconscious", "collapse"], "مغمى": ["unconscious", "collapse"], "مغمي": ["unconscious", "collapse"], "تشوش": ["confusion", "altered mental status"], "ارتباك": ["confusion", "altered mental status"], "شلل": ["paralysis", "stroke", "neurologic deficit"], "خدر": ["numbness", "neurologic deficit"], "ألم": ["pain"], "الم": ["pain"], "وجع": ["pain"], "حارق": ["burning pain", "burn"], "بطن": ["abdomen", "abdominal", "stomach"], "معدة": ["stomach", "abdomen"], "ظهر": ["back", "spine", "back pain"], "رقبة": ["neck", "airway", "trauma"], "عين": ["eye", "ocular", "vision"], "اذن": ["ear", "hearing"], "أذن": ["ear", "hearing"], "يد": ["hand", "upper limb"], "رجل": ["leg", "lower limb"], "ساق": ["leg", "limb", "extremity"], "ذراع": ["arm", "upper limb", "extremity"], "علاج": ["treatment", "therapy", "management"], "تدبير": ["management", "treatment"], "تصرف": ["what to do", "management", "first aid"], "اعمل": ["what to do", "management", "first aid"], "أسعف": ["first aid", "emergency treatment"], "اسعف": ["first aid", "emergency treatment"], "إسعاف": ["first aid", "emergency", "treatment"], "اسعاف": ["first aid", "emergency", "treatment"], "ماذا": ["what", "management"], "شلون": ["what to do", "management"], "ازاي": ["what to do", "management"], "كيف": ["how", "management"], "سوائل": ["fluids", "resuscitation", "hydration"], "محلول": ["IV fluid", "resuscitation", "lactated ringer"], "رينجر": ["lactated ringer", "ringer lactate", "fluid resuscitation"], "تعويض": ["resuscitation", "fluids"], "جفاف": ["dehydration", "fluids", "hydration"], "ترطيب": ["hydration", "fluids"], "بول": ["urine output", "kidney", "resuscitation"], "تبول": ["urine output", "kidney"], "ابني": ["my baby", "child", "newborn", "infant"], "بنتي": ["my baby", "child", "infant"], "عيلي": ["my child", "baby", "infant"], "طفلي": ["my child", "baby", "infant"], "مراتي": ["wife", "mother", "postpartum"], "مرتي": ["wife", "mother", "postpartum"], "امي": ["mother", "adult patient"], "أمي": ["mother", "adult patient"], "سكري": ["diabetes", "diabetic", "blood sugar", "glucose"], "سكر": ["diabetes", "blood sugar", "glucose"], "سكرية": ["diabetes", "diabetic"], "انسولين": ["insulin", "diabetes"], "جلوكوز": ["glucose", "blood sugar", "hypoglycemia"], "هبوط سكر": ["hypoglycemia", "low blood sugar", "glucose"], "هبوط": ["hypoglycemia", "low blood sugar", "fainting"], "ارتفاع سكر": ["hyperglycemia", "high blood sugar", "DKA"], "كيتو": ["ketoacidosis", "DKA", "diabetes"], "حماض": ["ketoacidosis", "DKA", "acidosis"], "ضغط": ["blood pressure", "hypertension"], "ضغط الدم": ["blood pressure", "hypertension"], "ضغط عالي": ["hypertension", "high blood pressure"], "ارتفاع الضغط": ["hypertension", "high blood pressure"], "انخفاض الضغط": ["hypotension", "low blood pressure", "shock"], "قصور القلب": ["heart failure", "cardiac failure"], "فشل القلب": ["heart failure", "cardiac failure"], "وذمة": ["edema", "swelling", "heart failure"], "ربو": ["asthma", "bronchospasm", "breathing"], "ربو القصبات": ["asthma", "bronchospasm"], "نوبة صرع": ["seizure", "epilepsy", "status epilepticus"], "اختلاج": ["seizure", "convulsion"], "غدة درقية": ["thyroid", "hypothyroidism"], "خمول الغدة": ["hypothyroidism", "thyroid"], "غيبوبة": ["coma", "unconscious", "myxedema"], "غيبوبه": ["coma", "unconscious"], "افاقه": ["recovery", "regain consciousness"], "جلطة دماغية": ["stroke", "cerebral infarction"], "احتشاء": ["infarction", "stroke", "myocardial infarction"], "شلل نصف": ["hemiplegia", "stroke", "paralysis"], "وجه مائل": ["facial droop", "stroke", "FAST"], "يد ضعيفة": ["arm weakness", "stroke", "FAST"], "كلام مش واضح": ["slurred speech", "stroke", "FAST"], "صداع شديد": ["severe headache", "meningitis", "stroke", "subarachnoid"], "صداع": ["headache", "meningitis", "stroke"], "رقبة متصلبة": ["neck stiffness", "meningitis"], "تيبس الرقبة": ["neck stiffness", "meningitis"], "تصلب الرقبة": ["neck stiffness", "meningitis"], "حساسية للضوء": ["photophobia", "meningitis"], "طفح": ["rash", "meningococcal", "meningitis"], "طفح جلدي": ["rash", "meningococcal", "petechiae"], "بقع حمراء": ["petechiae", "meningococcal", "rash"], "التهاب السحايا": ["meningitis", "meningococcal"], "سحايا": ["meningitis"], "ارتجاج": ["concussion", "head injury", "TBI"], "ضربة رأس": ["head injury", "concussion", "TBI"], "اصابة الرأس": ["head injury", "TBI", "concussion"], "مقياس جلاسكو": ["GCS", "glasgow coma scale", "head injury"], "ضعف في المخ": ["brain injury", "stroke", "head injury"], "نزيف مخي": ["intracranial hemorrhage", "brain bleed", "head injury"], "عين مختلفة": ["unequal pupils", "herniation", "head injury"], "حدقة": ["pupil", "eye", "head injury"], "نزيف شديد": ["hemorrhage", "hypovolemic shock", "blood loss"], "صدمة دموية": ["hypovolemic shock", "hemorrhage", "blood loss"], "نزف": ["bleeding", "hemorrhage", "blood loss"], "ضاغط": ["tourniquet", "hemorrhage control"], "حزام الضغط": ["tourniquet", "pressure", "hemorrhage"], "ضغط مباشر": ["direct pressure", "wound", "bleeding"], "توتر": ["stress", "anxiety", "acute stress reaction"], "صدمة نفسية": ["trauma", "PTSD", "psychological"], "اضطراب ما بعد الصدمة": ["PTSD", "trauma", "mental health"], "كآبة": ["depression", "grief", "mental health"], "اكتئاب": ["depression", "mental health"], "انتحار": ["suicide", "suicidal", "mental health"], "يريد ان يموت": ["suicidal ideation", "suicide risk"], "حزن": ["grief", "bereavement", "mental health"], "فقدان": ["loss", "grief", "bereavement"], "هلوسة": ["hallucination", "psychosis", "mental health"], "جنون": ["psychosis", "mental health"], "ذهان": ["psychosis", "delusion"], "وسواس": ["anxiety", "OCD", "mental health"], "اسعافات نفسية": ["psychological first aid", "PFA", "mental health"], "سم": ["poison", "poisoning", "toxic"], "مبيد": ["pesticide", "organophosphate", "poisoning"], "مبيدات": ["pesticide", "organophosphate", "poisoning"], "مبيد حشري": ["insecticide", "organophosphate", "SLUDGE"], "اعصاب": ["nerve agent", "organophosphate", "chemical weapon"], "غاز اعصاب": ["nerve agent", "sarin", "chemical weapon"], "سارين": ["sarin", "nerve agent", "organophosphate"], "اوكسيد الكربون": ["carbon monoxide", "CO poisoning"], "غاز الكربون": ["carbon monoxide", "CO poisoning"], "احتراق": ["combustion", "carbon monoxide", "inhalation"], "مولد كهرباء": ["generator", "carbon monoxide", "CO poisoning"], "لدغة": ["bite", "snakebite", "envenomation"], "لسعة ثعبان": ["snakebite", "venom", "envenomation"], "ثعبان": ["snake", "snakebite", "venom"], "افعى": ["viper", "snakebite", "venom"], "عقرب": ["scorpion", "envenomation", "sting"], "حامض": ["acid", "corrosive"], "ابتلع": ["ingested", "swallowed", "poisoning"], "كحول": ["alcohol", "poisoning"], "فحم نشط": ["activated charcoal", "poisoning treatment"], "يتقيأ": ["vomiting", "poisoning", "nausea"], "قيء": ["vomiting", "poisoning", "nausea"], "غثيان": ["nausea", "vomiting", "poisoning"], "بطن حاد": ["acute abdomen", "peritonitis", "surgical emergency"], "زائدة": ["appendicitis", "acute abdomen"], "انتان": ["peritonitis", "infection", "acute abdomen"], "التهاب الزائدة": ["appendicitis", "acute abdomen"], "التهاب الصفاق": ["peritonitis", "acute abdomen"], "انسداد معوي": ["intestinal obstruction", "bowel obstruction"], "حمل خارج الرحم": ["ectopic pregnancy", "acute abdomen"], "اسهال": ["diarrhea", "dehydration"], "اسهاله": ["diarrhea", "dehydration"], "اسهالات": ["diarrhea", "dehydration", "cholera"], "كوليرا": ["cholera", "diarrhea", "dehydration"], "محلول الإماهة": ["ORS", "oral rehydration", "dehydration"], "محلول إماهة": ["ORS", "rehydration", "dehydration"], "جفاف شديد": ["severe dehydration", "IV fluids", "shock"], "خلع كتف": ["shoulder dislocation", "dislocation"], "ألم الظهر": ["back pain", "spine", "lumbar"], "نخاع شوكي": ["spinal cord", "spine", "cauda equina"], "ذيل الفرس": ["cauda equina", "spine", "emergency"], "ذبحة": ["angina", "chest pain", "cardiac"], "احتشاء قلب": ["myocardial infarction", "heart attack", "chest pain"], "نوبة قلبية": ["heart attack", "myocardial infarction", "cardiac arrest"], "توقف القلب": ["cardiac arrest", "CPR", "resuscitation"], "استرواح": ["pneumothorax", "chest", "breathing"], "استرواح صدري": ["pneumothorax", "tension pneumothorax"], "ضغط مجوف": ["tension pneumothorax", "needle decompression"], "جرح الصدر": ["chest wound", "open chest wound", "sucking chest wound"], "جروح الصدر": ["chest wound", "penetrating chest", "pneumothorax"], "كسر الضلوع": ["rib fracture", "chest trauma", "flail chest"], "ضلوع": ["ribs", "rib fracture", "chest"], "التهاب رئوي": ["pneumonia", "lung infection", "respiratory"], "التهاب الرئة": ["pneumonia", "lung infection"], "ذات الرئة": ["pneumonia", "lung infection"], "جبيرة": ["splint", "immobilization", "fracture"], "جبس": ["cast", "plaster", "fracture"], "كسر مفتوح": ["open fracture", "compound fracture"], "كسر مركب": ["compound fracture", "open fracture"], "ورك": ["hip", "hip fracture", "pelvis"], "حوض": ["pelvis", "pelvic fracture", "hemorrhage"], "فخذ": ["femur", "thigh", "femur fracture"], "كعب": ["ankle", "ankle fracture", "sprain"], "متلازمة الحجرة": ["compartment syndrome", "fracture complication"], "انسداد وعاء": ["vascular compromise", "ischemia", "compartment"]};
  static const Map<String, List<String>> enExpansions = {"baby": ["baby", "infant", "newborn", "neonate", "child"], "infant": ["infant", "baby", "newborn", "neonate"], "newborn": ["newborn", "neonate", "baby", "infant"], "fever": ["fever", "high temperature", "temperature", "hot", "febrile"], "hypothermia": ["hypothermia", "cold", "low temperature", "warming", "warm", "skin-to-skin"], "cold": ["cold", "hypothermia", "low temperature", "warming", "warm"], "bleeding": ["bleeding", "hemorrhage", "blood loss", "haemorrhage"], "burn": ["burn", "burns", "burning", "thermal injury"], "choking": ["choking", "airway", "obstruction", "not breathing"], "fracture": ["fracture", "broken bone", "immobilization", "splint"], "shock": ["shock", "hemorrhage", "hypovolemic", "blood loss", "hypotension"], "wound": ["wound", "laceration", "injury", "bleeding", "hemorrhage"], "crush": ["crush injury", "compartment syndrome", "trauma"], "blast": ["blast injury", "explosion", "shrapnel", "trauma"], "dislocation": ["dislocation", "reduction", "joint injury"], "sprain": ["sprain", "strain", "RICE", "soft tissue"], "breathing": ["breathing", "respiratory", "airway", "breath"], "asthma": ["asthma", "bronchospasm", "wheeze", "inhaler", "salbutamol"], "pneumonia": ["pneumonia", "lung infection", "respiratory", "CURB-65"], "pneumothorax": ["pneumothorax", "chest", "tension pneumothorax", "needle decompression"], "chest": ["chest", "thoracic", "pneumothorax", "rib", "lung"], "stroke": ["stroke", "CVA", "FAST", "cerebral", "thrombolysis"], "seizure": ["seizure", "epilepsy", "convulsion", "status epilepticus"], "meningitis": ["meningitis", "meningococcal", "neck stiffness", "petechiae"], "headache": ["headache", "meningitis", "stroke", "subarachnoid"], "unconscious": ["unconscious", "loss of consciousness", "GCS", "coma"], "head": ["head injury", "TBI", "concussion", "GCS", "skull"], "diabetes": ["diabetes", "diabetic", "hypoglycemia", "DKA", "insulin"], "diabetic": ["diabetic", "diabetes", "hypoglycemia", "blood sugar"], "hypoglycemia": ["hypoglycemia", "low blood sugar", "glucose", "sugar"], "hypertension": ["hypertension", "blood pressure", "BP", "stroke"], "heart": ["heart", "cardiac", "heart failure", "pulmonary edema"], "epilepsy": ["epilepsy", "seizure", "convulsion", "status epilepticus"], "poison": ["poison", "poisoning", "toxic", "toxidrome"], "poisoning": ["poisoning", "toxic", "antidote", "activated charcoal"], "snakebite": ["snakebite", "venom", "envenomation", "antivenom"], "snake": ["snake", "snakebite", "venom", "antivenom"], "organophosphate": ["organophosphate", "pesticide", "SLUDGE", "nerve agent", "atropine"], "carbon": ["carbon monoxide", "CO poisoning", "smoke inhalation", "oxygen"], "corrosive": ["corrosive", "acid", "alkali", "chemical burn"], "diarrhea": ["diarrhea", "dehydration", "ORS", "rehydration"], "dehydration": ["dehydration", "ORS", "rehydration", "fluids"], "abdomen": ["abdomen", "acute abdomen", "peritonitis", "appendicitis"], "back": ["back pain", "spine", "lumbar", "cauda equina"], "suicide": ["suicide", "suicidal", "mental health", "crisis"], "ptsd": ["PTSD", "post-traumatic", "trauma", "mental health"], "psychosis": ["psychosis", "hallucination", "delusion", "mental health"], "grief": ["grief", "bereavement", "loss", "mental health"], "stress": ["stress", "acute stress reaction", "psychological first aid"]};

  static List<Map<String, dynamic>> _chunks = [];

  static final LinkedHashMap<String, List<Map<String, dynamic>>> _searchCache =
      LinkedHashMap<String, List<Map<String, dynamic>>>();
  static const int _searchCacheMax = 32;

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
    final normalized = isAr ? normalizeArabic(question) : question.toLowerCase().trim();
    final cacheKey = '${isAr ? 'a' : 'e'}|$normalized|$topK';

    if (_searchCache.containsKey(cacheKey)) {
      final cached = _searchCache.remove(cacheKey)!;
      _searchCache[cacheKey] = cached;
      return cached;
    }

    final termsToSearch = isAr ? _getEnglishTermsFromArabic(question) : _getEnglishTerms(question);

    final rawWords = (isAr ? normalizeArabic(question) : question.toLowerCase())
        .split(' ')
        .where((w) => w.length >= 3)
        .toList();

    final allSearchTerms = <String>{...termsToSearch, ...rawWords}.toList();

    final scored = <Map<String, dynamic>>[];
    for (final chunk in _chunks) {
      final text = chunk['text'] as String;
      final cn = chunk['cn'] as String;
      var score = 0;
      for (final w in allSearchTerms) {
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
    final results = scored.take(topK).toList();

    _searchCache[cacheKey] = results;
    while (_searchCache.length > _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    return results;
  }

  static String buildPrompt({
    required String question,
    required List<Map<String, dynamic>> chunks,
    String? toolDeclarations,
  }) {
    final arabic = isArabic(question);
    var systemPrompt = arabic ? systemPromptAr : systemPromptEn;
    if (toolDeclarations != null && toolDeclarations.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$toolDeclarations';
    }

    String context;
    if (chunks.isEmpty) {
      context = "NO_RELEVANT_CONTEXT";
    } else {
      final compact = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        final c = chunks[i];
        var text = (c['text'] as String).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.length > 280) {
          text = '${text.substring(0, 280)}...';
        }
        compact.add('[${i + 1}] source=${c['source'] ?? 'unknown'} score=${c['score'] ?? '?'}\n$text');
      }
      context = compact.join('\n\n---\n\n');
    }

    final userMsg = arabic
        ? "المرجع الطبي:\n$context\n\nالسؤال: $question"
        : "MEDICAL REFERENCE:\n$context\n\nQUESTION: $question";

    // Gemma 4 chat template (from google/gemma-4-E2B-it tokenizer):
    //   <bos><|turn>system\n[<|think|>\n]{system}<turn|>\n<|turn>user\n{user}<turn|>\n<|turn>model\n
    // Note the asymmetric markers (pipe-inside): <|turn> opens, <turn|> closes.
    // The <|think|> token at the top of the first system turn is the template's
    // enable_thinking switch — model emits <|channel>thought\n...<channel|>
    // before the visible answer. We always enable it; LlmService splits the
    // channels downstream.
    // <bos> is omitted here — llama.cpp's tokenizer adds it via add_special.
    return "<|turn>system\n<|think|>\n$systemPrompt<turn|>\n<|turn>user\n$userMsg<turn|>\n<|turn>model\n";
  }
}