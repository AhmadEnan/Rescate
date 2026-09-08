// Red-flag symptom triage layer - Dart port of eval/rag_mirror/triage.py.
//
// Pattern-matches a multilingual lexicon of emergency red-flag phrases
// against every user query BEFORE retrieval. On a hit, the matching
// emergency guidance is force-injected into context and an escalation
// frame is prepended. <1ms, no model call, fully auditable.
//
// Regression anchor (issue #14): 'انا صحيت من النوم لقيت ايدي منملة و
// مش حاسس بيها' (woke up with a numb hand = stroke red flag) must fire
// the stroke flag.

class RedFlag {
  final String id;
  final List<String> forms;
  final String title;
  final String anchorQuery;
  const RedFlag({
    required this.id,
    required this.forms,
    required this.title,
    required this.anchorQuery,
  });
}

const List<RedFlag> kRedFlags = [
  RedFlag(
    id: 'stroke',
    title:
        'possible STROKE (FAST: face drooping, arm weakness, speech difficulty, time-critical)',
    anchorQuery:
        'stroke sudden weakness or numbness on one side face drooping FAST signs what to do',
    forms: [
      'numb', "can't feel", 'cant feel', 'no feeling in', "won't move",
      'wont move', 'not moving', "doesn't move", 'doesnt move', 'paralyzed',
      'limp', 'face drooping', 'slurred', 'one side weak', 'weak on one side',
      'one side', 'منمل', 'تنميل', 'خدر', 'مش حاسس', 'مص قاسس', 'شلل',
      'ضعف في', 'تلثث', 'ارتباك مفاجئ', 'مش معايا', 'مش بيتحرك', 'رجلي',
      'رجله', 'ايدي',
    ],
  ),
  RedFlag(
    id: 'ingestion',
    title: 'suspected POISONING - time-critical even if the person seems fine',
    anchorQuery: 'poisoning swallowed pills or chemicals first aid emergency',
    forms: [
      'swallowed', 'drank', 'ate the', 'ate some', 'chewed', 'pill', 'pills',
      'bleach', 'detergent', 'medicine bottle', 'ابتلع', 'بلع', 'شرب',
      'حبوب', 'دوا', 'دواء', 'كلور',
    ],
  ),
  RedFlag(
    id: 'uncontrolled_bleeding',
    title: 'severe bleeding - pressure cannot be released',
    anchorQuery:
        'severe life-threatening bleeding control direct pressure tourniquet',
    forms: [
      'soaking through', 'blood everywhere', "won't stop bleeding",
      'wont stop bleeding', 'spurting', 'blood keeps coming', 'نزيف',
      'دم كتير', 'الدم غزير', 'ما بيوقفش', 'مش بيقف',
    ],
  ),
  RedFlag(
    id: 'airway_breathing',
    title: 'airway/breathing emergency',
    anchorQuery: 'choking blocked airway not breathing emergency steps',
    forms: [
      "can't breathe", 'cant breathe', 'not breathing', 'choking', 'gasping',
      'wheezing badly', 'throat closing', 'مش يتنفس', 'لا يتنفس', 'يخنق',
      'اختناق', 'مش قادر يتنفس', 'ضيق تنفس',
    ],
  ),
  RedFlag(
    id: 'unconscious',
    title:
        'unresponsive person - check breathing and pulse, recovery position if breathing',
    anchorQuery: 'unconscious person check breathing recovery position',
    forms: [
      'unconscious', 'not waking up', 'passed out', 'collapsed', 'no response',
      'فاقد الوعي', 'فاقد وعي', 'ما صحيش', 'غيبوبة', 'سقط مغشي عليه',
    ],
  ),
  RedFlag(
    id: 'head_trauma',
    title: 'possible head/spinal injury - minimize movement',
    anchorQuery: 'head injury danger signs when to worry skull fracture',
    forms: [
      'fell down the stairs', 'hit his head', 'hit her head', 'head injury',
      'قعت', 'سقط', 'ضرب في راسه', 'إصابة في الرأس', 'اصابة في الراس',
    ],
  ),
  RedFlag(
    id: 'anaphylaxis',
    title: 'possible ANAPHYLAXIS - airway swelling can be fatal within minutes',
    anchorQuery: 'severe allergic reaction anaphylaxis swollen airway what to do',
    forms: [
      'swollen face', 'swollen tongue', 'hives all over', 'throat swelling',
      'stung by', 'allergic reaction', 'anaphylaxis', 'تورم الوجه',
      'تورم اللسان', 'حساسية شديده', 'تحسس شديد',
      'تضعف التنفس من اللسعه',
    ],
  ),
  RedFlag(
    id: 'chest_pain',
    title: 'possible cardiac event',
    anchorQuery: 'heart attack signs chest pain what to do',
    forms: [
      'chest pain', 'chest pressure', 'pain in my chest', 'crushing chest',
      'الم في الصدر', 'ألم في الصدر', 'ضغط في الصدر', 'الصدر بتقيل',
    ],
  ),
  RedFlag(
    id: 'seizure',
    title: 'active or recent seizure',
    anchorQuery: 'seizure convulsion what to do during and after recovery position',
    forms: [
      'seizure', 'convulsion', 'shaking uncontrollably',
      'twitching and not respond', 'تشنج', 'صرع', 'اختلاج',
    ],
  ),
  RedFlag(
    id: 'severe_burn',
    title:
        'burn - depth and extent determine severity; painlessness suggests DEEP burn',
    anchorQuery: 'burn degrees classification deep third-degree burn treatment severity',
    forms: ['burned', 'burnt', 'burn on', 'scalded', 'حرق', 'احترق', 'اتحرق'],
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

/// Return every red flag whose surface form appears in [query].
List<TriageHit> triageQuery(String query) {
  final q = query.toLowerCase();
  final qn = normalizeArabic(q);
  final hits = <TriageHit>[];
  for (final flag in kRedFlags) {
    final matched = <String>[];
    for (final form in flag.forms) {
      if (q.contains(form) || normalizeArabic(form) == form
          ? qn.contains(normalizeArabic(form))
          : false) {
        matched.add(form);
      }
    }
    if (matched.isNotEmpty) hits.add(TriageHit(flag, matched));
  }
  return hits;
}

/// Mandatory reasoning frame prepended to the user message on a triage hit.
String escalationFrame(List<TriageHit> hits, bool arabic) {
  if (hits.isEmpty) return '';
  final titles = hits.map((h) => h.flag.title).join('; ');
  if (arabic) {
    return '⚠️ تنبيه تريج: يوجد مؤشرات على حالة طارئة ($titles). '
        'أجب وفق إطار الطوارئ: عالجها كحالة خطيرة حتى يثبت العكس، اذكر لماذا '
        'هذه الأعراض خطيرة تحديداً، وأعطِ خطوات فورية + متى تطلب رعاية عاجلة.';
  }
  return '⚠️ TRIAGE ALERT: the query contains red-flag signs ($titles). '
      'Answer using the emergency frame: treat as serious until proven otherwise, '
      'explain WHY these specific symptoms are dangerous, give immediate actions '
      'and when to seek urgent care.';
}
