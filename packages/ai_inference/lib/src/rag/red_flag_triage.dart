// Red-flag symptom triage layer - Dart port of eval/rag_mirror/triage.py.
//
// Pattern-matches a multilingual lexicon of emergency red-flag phrases
// against every user query BEFORE retrieval. On a hit, the matching
// emergency guidance is force-injected into context and an escalation
// frame is prepended. <1ms, no model call, fully auditable.
//
// MATCHING RULES (changed from bare substring):
//
// 1. Script-aware token boundaries. Every form matches only when it is not
//    embedded inside a longer word of the same script. Previously
//    `query.contains(form)` made 'pill' match "pillow", 'limp' match
//    "limping", 'حرق' match "حرقة" (heartburn) and 'ايدي' (my hand) fire the
//    STROKE flag. That produced a measured 42% false-positive rate on benign
//    input, and every false positive prepends a "⚠️ TRIAGE ALERT ... treat as
//    serious until proven otherwise" frame - i.e. it put healthy users into
//    emergency mode.
//
// 2. Inflections are listed explicitly rather than stripped by rule. Arabic
//    suffix stripping cannot distinguish 'منمل' -> 'منملة' (numb, a real stroke
//    sign, must match) from 'حرق' -> 'حرقة' (heartburn, must NOT match), so the
//    distinction is encoded as data. Add both spellings when adding a form.
//
// 3. Ambiguous forms carry a `near` gate: they fire only when a co-occurrence
//    signal is also present. 'swallowed' fires on "swallowed bleach" but not on
//    "swallowed my pride"; 'collapsed' fires for a person but not for a bridge.
//
// Regression anchors that must keep firing (issue #14, rag_v3_parity_test):
//   'انا صحيت من النوم لقيت ايدي منملة و مش حاسس بيها'  -> stroke
//   'صحيت لقيت ايدي منملة'                              -> stroke
//   'رجلهم مش بيتحرك و فيه شلل'                          -> stroke
//   'طفلي ابتلعت حبوب'                                  -> ingestion
//   'blood is soaking through the bandage'              -> uncontrolled_bleeding
//   "he can't breathe"                                  -> airway_breathing
//   'my hand is burned and looks bad but doesnt hurt'   -> severe_burn
//   'عندي ألم في الصدر و ضيق' / 'عنده الم في الصدر و ضيق' -> chest_pain
//   'عنده إصابة في الرأس'                               -> head_trauma
// And these must stay clean:
//   'how do I treat a blister from hiking'
//   'what should be in a first aid kit'
//   'ازاي اعالج لسعة نحل بسيطة'
//   'ازاي اعمل جبس لكسر بسيط في الصباع'
//   'ايه حاجات اساسية للاسعافات الاولية'

/// A single surface form, optionally gated on co-occurrence signals.
///
/// When [near] is non-empty the form only fires if at least one of those
/// strings is ALSO present in the query. Use it for forms that are real
/// emergency vocabulary but also common in benign everyday sentences.
///
/// When [notNear] is non-empty the form is suppressed if any of those strings
/// is present. Use it for non-literal uses ("collapsed laughing") and for
/// already-resolved episodes ("passed out ... she is fine now").
class RedFlagForm {
  final String text;
  final List<String> near;
  final List<String> notNear;
  const RedFlagForm(this.text,
      {this.near = const <String>[], this.notNear = const <String>[]});
}

class RedFlag {
  final String id;
  final List<RedFlagForm> forms;
  final String title;
  final String anchorQuery;
  const RedFlag({
    required this.id,
    required this.forms,
    required this.title,
    required this.anchorQuery,
  });

  /// Plain surface strings, for tooling/introspection.
  List<String> get formTexts => [for (final f in forms) f.text];
}

const List<RedFlag> kRedFlags = [
  RedFlag(
    id: 'stroke',
    title:
        'possible STROKE (FAST: face drooping, arm weakness, speech difficulty, time-critical)',
    anchorQuery:
        'stroke sudden weakness or numbness on one side face drooping FAST signs what to do',
    forms: [
      // 'limp', 'one side', 'رجلي', 'رجله' and 'ايدي' were removed: none is a
      // stroke sign, and each fired on everyday speech ("my dog is limping",
      // "my leg gets tired", "my hand hurts from writing").
      RedFlagForm('numb'),
      RedFlagForm('numbness'),
      RedFlagForm("can't feel"),
      RedFlagForm('cant feel'),
      RedFlagForm('cannot feel'),
      RedFlagForm('no feeling in'),
      RedFlagForm("won't move"),
      RedFlagForm('wont move'),
      RedFlagForm('not moving'),
      RedFlagForm("doesn't move"),
      RedFlagForm('doesnt move'),
      RedFlagForm('paralyzed'),
      RedFlagForm('paralysed'),
      RedFlagForm('paralysis'),
      RedFlagForm('face drooping'),
      RedFlagForm('drooping face'),
      RedFlagForm('facial droop'),
      RedFlagForm('slurred'),
      RedFlagForm('slurring'),
      RedFlagForm('weak on one side'),
      RedFlagForm('one side weak'),
      RedFlagForm('weakness on one side'),
      RedFlagForm('one side of my body'),
      RedFlagForm('one side of his body'),
      RedFlagForm('hemiparesis'),
      RedFlagForm('منمل'),
      RedFlagForm('منملة'),
      RedFlagForm('تنميل',
          near: ['مفاجئ', 'مفاجئة', 'فجأة', 'نص', 'جانب', 'وجه', 'ايد', 'يد',
                 'دراع', 'لسان', 'كلام', 'شلل', 'ضعف']),
      RedFlagForm('خدر'),
      RedFlagForm('مش حاسس'),
      RedFlagForm('مش حاسة'),
      RedFlagForm('شلل'),
      RedFlagForm('شلل نصفي'),
      RedFlagForm('ضعف في'),
      RedFlagForm('تلثث'),
      RedFlagForm('ارتباك مفاجئ'),
      RedFlagForm('مش بيتحرك'),
      RedFlagForm('مش بتتحرك'),
      RedFlagForm('نص الجسم'),
    ],
  ),
  RedFlag(
    id: 'ingestion',
    title: 'suspected POISONING - time-critical even if the person seems fine',
    anchorQuery: 'poisoning swallowed pills or chemicals first aid emergency',
    forms: [
      // Bare 'شرب' (drank) and 'دوا' (medicine) were removed: drinking water and
      // taking a routine pill are not poisonings. They now require a signal.
      RedFlagForm('swallowed',
          near: ['pill', 'pills', 'tablet', 'bleach', 'chemical', 'detergent',
                 'poison', 'medicine', 'bottle', 'substance', 'battery',
                 'button', 'drug', 'accidentally', 'by mistake', 'amount']),
      RedFlagForm('swallow',
          near: ['pill', 'pills', 'tablet', 'bleach', 'chemical', 'detergent',
                 'poison', 'bottle', 'battery', 'button']),
      RedFlagForm('drank',
          near: ['bleach', 'chemical', 'detergent', 'poison', 'medicine',
                 'pills', 'too much', 'alcohol', 'unknown', 'petrol',
                 'kerosene', 'acid']),
      RedFlagForm('ate the', near: ['pills', 'tablets', 'battery', 'chemical']),
      RedFlagForm('ate some', near: ['pills', 'tablets', 'battery', 'chemical']),
      RedFlagForm('chewed',
          near: ['pill', 'tablet', 'battery', 'button', 'chemical', 'medicine',
                 'glass']),
      RedFlagForm('pill',
          near: ['swallow', 'swallowed', 'took', 'overdose', 'too many',
                 'whole bottle', 'handful', 'chewed']),
      RedFlagForm('pills',
          near: ['swallow', 'swallowed', 'took', 'overdose', 'too many',
                 'whole bottle', 'handful', 'chewed', 'bottle']),
      RedFlagForm('bleach'),
      RedFlagForm('detergent'),
      RedFlagForm('caustic'),
      RedFlagForm('overdose'),
      RedFlagForm('took too many'),
      RedFlagForm('whole bottle'),
      RedFlagForm('poisoning'),
      RedFlagForm('poisoned'),
      RedFlagForm('ابتلع'),
      RedFlagForm('ابتلعت'),
      RedFlagForm('بلع'),
      RedFlagForm('بلعت'),
      RedFlagForm('حبوب'),
      RedFlagForm('كلور'),
      RedFlagForm('تسمم'),
      RedFlagForm('جرعة زايدة'),
      RedFlagForm('دوا زيادة'),
      RedFlagForm('شرب كلور'),
      RedFlagForm('شرب دوا'),
    ],
  ),
  RedFlag(
    id: 'uncontrolled_bleeding',
    title: 'severe bleeding - pressure cannot be released',
    anchorQuery:
        'severe life-threatening bleeding control direct pressure tourniquet',
    forms: [
      RedFlagForm('soaking through'),
      RedFlagForm('soaked through'),
      RedFlagForm('blood everywhere'),
      RedFlagForm("won't stop bleeding"),
      RedFlagForm('wont stop bleeding'),
      RedFlagForm('spurting'),
      RedFlagForm('blood keeps coming'),
      RedFlagForm('severe bleeding'),
      RedFlagForm('bleeding heavily'),
      RedFlagForm('uncontrolled bleeding'),
      RedFlagForm('blood is pouring'),
      RedFlagForm('نزيف'),
      RedFlagForm('نزيف شديد'),
      RedFlagForm('دم كتير'),
      RedFlagForm('الدم غزير'),
      RedFlagForm('دم غزير'),
      RedFlagForm('ما بيوقفش'),
      RedFlagForm('مش بيقف'),
    ],
  ),
  RedFlag(
    id: 'airway_breathing',
    title: 'airway/breathing emergency',
    anchorQuery: 'choking blocked airway not breathing emergency steps',
    forms: [
      RedFlagForm("can't breathe"),
      RedFlagForm('cant breathe'),
      RedFlagForm('cannot breathe'),
      RedFlagForm('not breathing'),
      RedFlagForm("isn't breathing"),
      RedFlagForm('stopped breathing'),
      RedFlagForm('choking'),
      RedFlagForm('gasping'),
      RedFlagForm('wheezing badly'),
      RedFlagForm('throat closing'),
      RedFlagForm('blocked airway'),
      RedFlagForm('airway blocked'),
      RedFlagForm('مش يتنفس'),
      RedFlagForm('مش بيتنفس'),
      RedFlagForm('لا يتنفس'),
      RedFlagForm('يخنق'),
      RedFlagForm('اختناق'),
      RedFlagForm('مش قادر يتنفس'),
      RedFlagForm('ضيق تنفس'),
      RedFlagForm('مش قادر ياخد نفس'),
    ],
  ),
  RedFlag(
    id: 'unconscious',
    title:
        'unresponsive person - check breathing and pulse, recovery position if breathing',
    anchorQuery: 'unconscious person check breathing recovery position',
    forms: [
      RedFlagForm('unconscious'),
      RedFlagForm('unresponsive'),
      RedFlagForm('not waking up'),
      RedFlagForm('not responding'),
      RedFlagForm('passed out',
          notNear: ['is fine now', 'was fine', 'she is fine', 'he is fine',
                    'recovered', 'ok now', 'fine now', 'came round',
                    'came around', 'feeling better']),
      RedFlagForm('fainted',
          notNear: ['is fine now', 'was fine', 'recovered', 'ok now',
                    'fine now', 'came round', 'came around']),
      RedFlagForm('no response'),
      // Gated: "the old bridge collapsed" is not a medical emergency.
      RedFlagForm('collapsed',
          near: ['he', 'she', 'person', 'someone', 'man', 'woman', 'child',
                 'baby', 'boy', 'girl', 'patient', 'casualty', 'victim', 'dad',
                 'mom', 'father', 'mother', 'friend', 'brother', 'sister',
                 'husband', 'wife'],
          notNear: ['laughing', 'into chaos', 'economy', 'market', 'meeting',
                    'is fine now', 'was fine', 'recovered', 'ok now',
                    'fine now']),
      RedFlagForm('فاقد الوعي'),
      RedFlagForm('فاقد وعي'),
      RedFlagForm('ما صحيش'),
      RedFlagForm('غيبوبة'),
      RedFlagForm('سقط مغشي عليه'),
      RedFlagForm('مغشي عليه'),
    ],
  ),
  RedFlag(
    id: 'head_trauma',
    title: 'possible head/spinal injury - minimize movement',
    anchorQuery: 'head injury danger signs when to worry skull fracture',
    forms: [
      // Bare 'سقط' (fell) / 'قعت' were removed: "dropped my phone", "my son fell
      // while playing and got up fine" are not head injuries.
      RedFlagForm('fell down the stairs'),
      RedFlagForm('hit his head'),
      RedFlagForm('hit her head'),
      RedFlagForm('hit my head'),
      RedFlagForm('hit the head'),
      RedFlagForm('head injury'),
      RedFlagForm('head trauma'),
      RedFlagForm('skull fracture'),
      RedFlagForm('banged his head'),
      RedFlagForm('banged her head'),
      RedFlagForm('ضرب في راسه'),
      RedFlagForm('إصابة في الرأس'),
      RedFlagForm('اصابة في الراس'),
      RedFlagForm('وقع على راسه'),
      RedFlagForm('خبطة في الراس'),
    ],
  ),
  RedFlag(
    id: 'anaphylaxis',
    title: 'possible ANAPHYLAXIS - airway swelling can be fatal within minutes',
    anchorQuery: 'severe allergic reaction anaphylaxis swollen airway what to do',
    forms: [
      RedFlagForm('swollen face'),
      RedFlagForm('swollen tongue'),
      RedFlagForm('swollen throat'),
      RedFlagForm('throat swelling'),
      RedFlagForm('hives all over'),
      RedFlagForm('widespread hives'),
      RedFlagForm('stung by'),
      RedFlagForm('anaphylaxis'),
      RedFlagForm('allergic reaction',
          near: ['swollen', 'swelling', 'hives', 'throat', 'breath', 'severe',
                 'badly', 'rash', 'spreading']),
      RedFlagForm('تورم الوجه'),
      RedFlagForm('تورم اللسان'),
      RedFlagForm('حساسية شديده'),
      RedFlagForm('حساسية شديدة'),
      RedFlagForm('تحسس شديد'),
      RedFlagForm('تضعف التنفس من اللسعه'),
    ],
  ),
  RedFlag(
    id: 'chest_pain',
    title: 'possible cardiac event',
    anchorQuery: 'heart attack signs chest pain what to do',
    forms: [
      RedFlagForm('chest pain'),
      RedFlagForm('chest pressure'),
      RedFlagForm('pain in my chest'),
      RedFlagForm('pain in his chest'),
      RedFlagForm('pain in her chest'),
      RedFlagForm('crushing chest'),
      RedFlagForm('الم في الصدر'),
      RedFlagForm('ألم في الصدر'),
      RedFlagForm('ضغط في الصدر'),
      RedFlagForm('الصدر بتقيل'),
      RedFlagForm('وجع في الصدر'),
    ],
  ),
  RedFlag(
    id: 'seizure',
    title: 'active or recent seizure',
    anchorQuery: 'seizure convulsion what to do during and after recovery position',
    forms: [
      RedFlagForm('seizure'),
      RedFlagForm('convulsion'),
      RedFlagForm('convulsing'),
      RedFlagForm('shaking uncontrollably'),
      RedFlagForm('twitching and not respond'),
      RedFlagForm('تشنج'),
      RedFlagForm('تشنجات'),
      RedFlagForm('صرع'),
      RedFlagForm('اختلاج'),
    ],
  ),
  RedFlag(
    id: 'severe_burn',
    title:
        'burn - depth and extent determine severity; painlessness suggests DEEP burn',
    anchorQuery: 'burn degrees classification deep third-degree burn treatment severity',
    forms: [
      // 'burn' (the noun) was missing entirely, so "A person has a severe burn"
      // did NOT fire while the Arabic equivalent did. Gated so that burning your
      // tongue on tea is not treated as a major burn.
      RedFlagForm('burn',
          near: ['severe', 'third', 'third-degree', 'deep', 'large', 'major',
                 'extensive', 'degree', 'hand', 'arm', 'leg', 'face', 'body',
                 'chest', 'back', 'child', 'baby', 'person', 'skin', 'scald']),
      RedFlagForm('burns',
          near: ['severe', 'third', 'deep', 'large', 'major', 'extensive',
                 'degree', 'body', 'person', 'skin']),
      RedFlagForm('burned',
          near: ['severe', 'third', 'deep', 'large', 'major', 'extensive',
                 'degree', 'hand', 'arm', 'leg', 'face', 'body', 'chest',
                 'back', 'child', 'baby', 'person', 'skin']),
      RedFlagForm('burnt',
          near: ['severe', 'third', 'deep', 'large', 'major', 'hand', 'arm',
                 'leg', 'face', 'body', 'person', 'skin']),
      RedFlagForm('burning',
          near: ['severe', 'third', 'deep', 'large', 'major', 'extensive',
                 'body', 'person', 'skin', 'clothes', 'clothing']),
      RedFlagForm('scalded'),
      RedFlagForm('scald'),
      RedFlagForm('third degree'),
      RedFlagForm('third-degree'),
      RedFlagForm('severe burn'),
      // 'حرق' must NOT match 'حرقة' (heartburn) - token boundary handles that.
      RedFlagForm('حرق'),
      RedFlagForm('حروق'),
      RedFlagForm('احترق'),
      RedFlagForm('اتحرق'),
      RedFlagForm('حرق شديد'),
    ],
  ),
];

class TriageHit {
  final RedFlag flag;
  final List<String> matched;
  const TriageHit(this.flag, this.matched);
}

/// Light Arabic normalization: strip diacritics/tatweel, unify alef/yaa/ta-marbuta.
String normalizeArabic(String text) {
  final sb = StringBuffer();
  for (final ch in text.runes) {
    // tashkeel range + superscript alef
    if ((ch >= 0x64B && ch <= 0x652) || ch == 0x670) continue;
    if (ch == 0x640) continue; // tatweel
    var c = String.fromCharCode(ch);
    c = c.replaceAll(RegExp('[أإآٱ]'), 'ا');
    c = c.replaceAll('ى', 'ي').replaceAll('ة', 'ه');
    sb.write(c);
  }
  return sb.toString();
}

/// True when [s] contains any Arabic-script code point.
///
/// Shared by the triage lexicon and by retrieval's similarity floor, which is
/// calibrated per script (see [kMinHitScoreLatin] in `rag_v3.dart`).
bool isArabicScript(String s) =>
    s.runes.any((c) => c >= 0x0600 && c <= 0x06FF);

/// Token-boundary pattern for [form].
///
/// Script-aware: a form is delimited by "not a letter of its own script" on
/// both sides. Plain `\b` is unusable here because Dart's `\w` is ASCII-only,
/// so it would never match an Arabic boundary.
final Map<String, RegExp> _formPatternCache = {};

RegExp _formPattern(String form) {
  return _formPatternCache.putIfAbsent(form, () {
    final esc = RegExp.escape(form);
    if (isArabicScript(form)) {
      return RegExp('(?<![\\u0600-\\u06FF])$esc(?![\\u0600-\\u06FF])');
    }
    return RegExp("(?<![A-Za-z])$esc(?![A-Za-z])");
  });
}

/// Return every red flag whose surface form appears in [query] as a token.
///
/// Matching is done against both the raw query and its Arabic-normalized form,
/// so diacritic/tatweel differences and alef/yaa variants do not hide a match.
List<TriageHit> triageQuery(String query) {
  final q = query.toLowerCase();
  final qn = normalizeArabic(q);
  final hits = <TriageHit>[];
  for (final flag in kRedFlags) {
    final matched = <String>[];
    for (final form in flag.forms) {
      final f = form.text.toLowerCase();
      final raw = _formPattern(f).hasMatch(q);
      final nrm = _formPattern(normalizeArabic(f)).hasMatch(qn);
      if (!raw && !nrm) continue;
      // Ambiguous form: require a co-occurrence signal before firing, and
      // honour any suppression signal (non-literal or resolved episode).
      if (form.near.isNotEmpty && !_nearPresent(form.near, q, qn)) continue;
      if (form.notNear.isNotEmpty && _notNearPresent(form.notNear, q, qn)) {
        continue;
      }
      matched.add(form.text);
    }
    if (matched.isNotEmpty) hits.add(TriageHit(flag, matched));
  }
  return hits;
}

/// True when at least one co-occurrence signal is present.
///
/// Matched with the same script-aware token boundaries as the forms themselves.
/// Plain substring matching was a bug: 'he' matched inside "t**he** old bridge",
/// so "the old bridge collapsed" satisfied the person gate and fired the
/// UNCONSCIOUS flag.
bool _nearPresent(List<String> near, String q, String qn) {
  for (final n in near) {
    final t = n.toLowerCase();
    if (_formPattern(t).hasMatch(q) ||
        _formPattern(normalizeArabic(t)).hasMatch(qn)) {
      return true;
    }
  }
  return false;
}

/// True when any suppression signal is present.
///
/// These are phrases, not single tokens, so substring matching is correct here
/// ("she is fine now" must match regardless of surrounding punctuation).
bool _notNearPresent(List<String> notNear, String q, String qn) {
  for (final n in notNear) {
    final t = n.toLowerCase();
    if (q.contains(t) || qn.contains(normalizeArabic(t))) return true;
  }
  return false;
}

/// Mandatory reasoning frame prepended to the user message on a triage hit.
///
/// This frame also carries the warzone framing that used to sit in the always-on
/// system prompt (no reachable ambulance, prolonged care, prevent deterioration).
/// Moving it here means a greeting or an ordinary question is never briefed on
/// tourniquets, while a genuine red flag still gets the austere-environment
/// assumptions it needs.
String escalationFrame(List<TriageHit> hits, bool arabic) {
  if (hits.isEmpty) return '';
  final titles = hits.map((h) => h.flag.title).join('; ');
  // The urgency must be UNCONDITIONAL. An earlier draft ended with "never make
  // reaching a hospital a precondition of the advice", meant to stop the model
  // withholding first aid in a warzone. Measured effect: the model read it as
  // licence to hedge, and answered a stroke with "seek urgent care IF symptoms
  // worsen" (rf_stroke_ar) - i.e. it downgraded a time-critical emergency to
  // watch-and-wait. The no-hospital clause is now a reason to ALSO give steps,
  // never a reason to soften the referral.
  if (arabic) {
    return '⚠️ تنبيه تريج: يوجد مؤشرات على حالة طارئة ($titles). اذكر السبب '
        'الخطير المحتمل ولماذا هذه الأعراض خطيرة تحديداً. قل بوضوح وبدون شروط '
        'إن الحالة تحتاج رعاية طبية طارئة الآن، ولا تنتظر لترى إن كانت تتحسن. '
        'أعطِ الخطوات الفورية أولاً ثم ما يجب مراقبته، حتى يُساعد الشخص فعلاً '
        'حتى لو تعذّر الوصول إلى إسعاف أو مستشفى.';
  }
  return '⚠️ TRIAGE ALERT: the query contains red-flag signs ($titles). '
      'Name the most likely serious cause and say why these specific signs are '
      'dangerous. State clearly and without conditions that this needs '
      'emergency medical care now - do not wait to see whether it improves. '
      'Give the immediate actions first as short numbered steps, then what to '
      'watch for, so the person is genuinely helped even if no ambulance or '
      'hospital can be reached.';
}
