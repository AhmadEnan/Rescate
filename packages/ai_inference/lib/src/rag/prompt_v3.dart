// prompt_v3: register-aware system prompts (EN/AR) + Gemma-4 raw template
// builder. Ported from eval/rag_mirror/legacy_rag.py (validated).
//
// ── Why this prompt is short ────────────────────────────────────────────────
//
// The previous version was 2,275 chars (~615 tokens) and opened with an
// enumerated thinking order:
//
//     "Order of thinking: 1. SAFETY FIRST: ... 2. IMMEDIATE ACTIONS: ...
//      3. PROLONGED CARE: ... 4. ESCALATION: ..."
//
// Gemma-4-E2B is a 2B model, and it treated that enumeration as an *answer
// template* rather than an instruction about reasoning. Asked "hi", it replied
// with a generic mass-casualty briefing, echoing the section labels verbatim:
//
//     "1. SAFETY FIRST: Assess the scene for ongoing danger...
//      2. IMMEDIATE ACTIONS: If there is severe bleeding, apply direct
//      pressure... 3. PROLONGED CARE: Monitor for signs of shock..."
//
// The same hijack produced a 145-word emergency template in answer to
// "who are you and what can you do?" (correct answer: 45 words). The prompt
// also said "No greeting, disclaimer, or vague intake", which explicitly
// forbade the one response a greeting deserves.
//
// So this version:
//   * states the register rule FIRST, so a greeting is answered as a greeting;
//   * uses prose with no enumerated scaffold and no all-caps section labels,
//     because those labels were what the model regurgitated;
//   * moves the warzone framing (no ambulance, prolonged care, blast injury)
//     OUT of the always-on prompt and INTO the escalation frame, which is only
//     prepended when red-flag triage actually fires. A greeting is therefore no
//     longer briefed on tourniquets.
//
// On the MT6893 device this is also the single biggest latency lever: prefill
// runs at 4.58 tok/s, so dropping the system prompt from ~615 tokens to a
// measured 159 (EN) / 193 (AR) saves roughly 90-100 s of time-to-first-token on
// every turn.

const String kSystemPromptEnV3 =
    "You are Rescate, an offline first-aid assistant. Match the user's "
    'register: a greeting, thanks, or a general question (including one about '
    'yourself) gets a short ordinary reply, not emergency instructions. For a '
    'medical question, give the '
    'safest immediate actions first as short numbered steps, then what to '
    'watch for. Ask at most one question, and only after giving the steps. Use '
    'only the medical reference and never invent facts. Never recommend or '
    'dose prescription medicines: say a medical professional must decide, and '
    'give the safe first-aid alternative. Read the symptoms described rather '
    'than the label the user gives them - a deep burn can be painless, and '
    'feeling fine after a fall or an ingestion does not rule out serious '
    'injury, so state the danger signs to watch. Be concise.';

const String kSystemPromptArV3 =
    'أنت Rescate، مساعد إسعافات أولية يعمل دون اتصال. طابق أسلوب السؤال: '
    'التحية أو الشكر أو السؤال العام (بما في ذلك عن نفسك) يقابلها رد قصير عادي '
    'وليس تعليمات طوارئ. '
    'في السؤال الطبي أعطِ الإجراءات الفورية الآمنة أولاً كخطوات قصيرة مرقمة ثم '
    'ما يجب مراقبته. اسأل سؤالاً واحداً كحد أقصى وبعد الخطوات فقط. استخدم '
    'المرجع الطبي ولا تخترع معلومات. لا تصف جرعات أدوية بوصفة: القرار لمختص '
    'طبي وأعطِ البديل الإسعافي الآمن. اقرأ الأعراض المذكورة لا التسمية: الحرق '
    'العميق قد يكون بلا ألم، والشعور بأن الشخص بخير بعد سقوط أو ابتلاع لا ينفي '
    'الإصابة الخطيرة، فاذكر علامات الخطر. كن موجزاً.';

/// Neutral prefilled thought used to close Gemma-4's reasoning channel cheaply.
///
/// The previous text asserted "The question is clear ... give safe immediate
/// actions when relevant", which primed emergency actions even for a greeting.
/// This version makes no claim about the question's content.
const String kFastThoughtEn = 'Answer the user directly and concisely.';
const String kFastThoughtAr = 'أجب المستخدم مباشرة وبإيجاز.';

/// Builds the raw Gemma-4 template prompt (thinking disabled, fast prefill).
/// Mirrors the app's LegacyRag.buildPrompt structure with the v3 system text.
/// [toolDeclarations] / [enableThinking] match LegacyRag semantics so
/// tool-enabled turns keep their schemas on the v3 path too.
String buildGemmaPromptV3({
  required String context,
  required String question,
  required bool arabic,
  String? toolDeclarations,
  bool enableThinking = false,
}) {
  var system = arabic ? kSystemPromptArV3 : kSystemPromptEnV3;
  if (toolDeclarations != null && toolDeclarations.isNotEmpty) {
    system = '$system\n\n$toolDeclarations';
  }
  final user = arabic
      ? 'المرجع الطبي:\n$context\n\nالسؤال: $question'
      : 'MEDICAL REFERENCE:\n$context\n\nQUESTION: $question';
  final fast = arabic ? kFastThoughtAr : kFastThoughtEn;
  final modelPrefix =
      enableThinking ? '' : '<|channel>thought\n$fast<channel|>\n';
  return '<|turn>system\n<|think|>\n$system<turn|>\n'
      '<|turn>user\n$user<turn|>\n'
      '<|turn>model\n$modelPrefix';
}

/// Native chat template path for non-Gemma eval models (used by harness only).
({String system, String user}) buildChatMessagesV3({
  required String context,
  required String question,
  required bool arabic,
  required String? escalationFrame,
}) {
  final system = arabic ? kSystemPromptArV3 : kSystemPromptEnV3;
  final body = arabic
      ? 'المرجع الطبي:\n$context\n\nالسؤال: $question'
      : 'MEDICAL REFERENCE:\n$context\n\nQUESTION: $question';
  final user = (escalationFrame == null || escalationFrame.isEmpty)
      ? body
      : '$escalationFrame\n\n$body';
  return (system: system, user: user);
}
