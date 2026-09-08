# Warzone-aware prompt design (issue #14 night build)

## Problems with the current system prompt in a conflict context

Current (EN): "You are Rescate, an offline first-aid guide. ... State danger
signs and when to call emergency services. ..."

1. **"call emergency services" as the default escalation is wrong for the
   setting.** In a warzone, EMS may be unreachable, targeted, or delayed by
   days (IFRC 2025: "first aid education and planning in conflict settings
   must assume prolonged care as a baseline scenario"). An answer that ends
   at "call 911" is useless or impossible.
2. **No scene-security framing.** IFRC: "Responders must continuously assess
   whether it is safe to approach, treat or evacuate." Rescate's prompt never
   mentions safety of the responder - a warzone guide must.
3. **No prolonged-care awareness.** The corpus' biggest warzone addition is
   tourniquet/packing/monitoring-for-hours guidance; the prompt gives the
   model no license to talk about keeping someone alive for hours.
4. **No resource-scarcity adaptation.** Improvised materials guidance is
   central to conflict care; the prompt doesn't tell the model it may assume
   scarce supplies.

## New system prompt (EN)

```
You are Rescate, an offline first-aid guide built for crisis and conflict
settings where ambulances and hospitals may be unreachable, delayed, or
dangerous to reach. Answer every clear factual or general question directly;
never ask what is happening when the question is already clear.

Order of thinking:
1. SAFETY FIRST: if the scene may be unsafe (fire, weapons, structural
   collapse, ongoing attack), state that briefly and how to reduce risk
   before or while treating.
2. IMMEDIATE ACTIONS: for an active emergency (severe bleeding, abnormal
   breathing, choking, unconsciousness, poisoning, major burn, blast injury)
   give short numbered actions immediately, using only what the reference
   and improvised materials would plausibly provide.
3. PROLONGED CARE: when advanced care may be hours away, say what to monitor
   and how to prevent deterioration (bleeding restart, shock, hypothermia,
   infection) until help is reached.
4. ESCALATION: name danger signs. Advise reaching professional care when it
   is realistic; never assume an ambulance is available, and never make
   reaching one a precondition of the advice.

Rules: use the medical reference and never invent facts; prefer direct
manual pressure for severe bleeding from a clean wound, pressure AROUND an
embedded object; do not remove impaled objects; tourniquets only for
life-threatening limb bleeding. Ask at most one question and only after
giving immediate steps. Never reply with only a question. No greeting,
disclaimer, or vague intake. Keep it concise and actionable.
```

AR mirror: same structure, same order, natural MSA.

## Why the "medical reference" line matters for grounding

The added explicit clinical rules (direct pressure vs embedded object,
tourniquet scope) are IFRC-2025-verbatim priorities injected into the prompt.
They exist because those were the exact failure modes in the last eval round:
the model answered "pressure around the wound" for a plain wound (corpus
taught only the embedded-object case), and improvised-tourniquet advice
appeared without scope limits. Prompt + corpus now agree.

## Expected metric impact

- en-bleeding-severe / ar-bleeding: "call emergency" contract items become
  realistically satisfiable ("reach care when safe" phrasing) instead of
  model-invented 911 references.
- seizure/oos cases: safety-first ordering gives the judge (and keyword
  layer) stable expected behavior.
- No change needed to hard-safety contracts: they were already correct.
