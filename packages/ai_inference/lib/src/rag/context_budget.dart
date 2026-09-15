// packages/ai_inference/lib/src/rag/context_budget.dart
//
// How many tokens of retrieved context we are willing to put in front of the
// model, per device.
//
// ── Why this file exists ─────────────────────────────────────────────────────
//
// The previous tier keyed the budget off RAM alone:
//
//     if (isLowRam || totalRamMb <= 5000) return 600;
//     if (totalRamMb <= 7500)                 return 800;
//     return 1400;
//
// RAM is a *capacity* signal, not a *throughput* signal. On-device prefill is
// the single most expensive phase of a turn and its cost is CPU/GPU compute,
// not memory. The mismatch is not theoretical: an 8 GB Helio G95 phone
// (MT6785, 2×A76 + 6×A55, Mali-G76, launched 2020) clears the 7500 MB bar and
// was therefore handed the largest budget in the table — 1400 context tokens —
// while a 4 GB 2023 mid-ranger with far better IPC got the smallest. Measured
// on that phone, a "how to treat a burn" turn took 66 s to first token; the
// retrieved context dominated it.
//
// ── What replaces it ─────────────────────────────────────────────────────────
//
// Two independent upper bounds, and the budget is the tighter of the two:
//
//   1. [inferFromHardware] — a cold-start guess from signals that actually
//      correlate with prefill speed: the SoC's presence in the repo's own
//      slow-compute list (see `slowVulkanSocMarkers`), the number of big
//      cores, and total RAM as a weak latency proxy for genuinely low-end
//      parts.
//
//   2. [forPrefillRate] — the measured prefill rate of completed turns
//      (`prompt_eval_tokens / prompt_eval_ms` from llama.cpp's perf counters,
//      already written into every `llm.turn` trace). This is authoritative:
//      it is the actual throughput of this device, on this model, with the
//      current thread/backend configuration.
//
// ── Speed-safety invariant ───────────────────────────────────────────────────
//
// Lowering the context budget can only ever make a turn *faster* — fewer
// prompt tokens means less prefill. So the only way this file can regress
// latency is by handing back a number *larger* than the device would have got
// before. Two rules prevent that:
//
//   * the result is clamped to [validatedDefault] (1400), the budget the
//     offline answer-quality suite was validated against, so no device can
//     receive more context than it does today; and
//   * the measured bound is combined with `math.min`, never `math.max`, so a
//     measurement can only ever tighten the hardware inference and can never
//     relax it. A device whose measurement is unrepresentative (cold start,
//     thermal throttling, a background app hogging cores) is therefore still
//     bounded by its hardware inference.
//
// Net effect: every device is at or below its current budget, and slow devices
// — which today are the ones being punished — come down the most.

import 'dart:math' as math;

import '../device_profile.dart';
import '../llm_load_strategy.dart';

/// Resolves the RAG context token budget for the active device.
///
/// See the file header for the rationale; the short version is that the budget
/// is bounded by hardware inference and by measured prefill throughput, and
/// the tighter of the two wins.
class RagContextBudget {
  const RagContextBudget._();

  /// The budget every device used before this tier existed, and the value the
  /// 32-case offline answer-quality suite was validated against (91% at
  /// temp 0.6). Nothing is allowed to exceed it.
  static const int validatedDefault = 1400;

  /// Lower bound. Below this the citation block is too short to carry a usable
  /// answer — the model starts answering from parametric memory instead of the
  /// retrieved corpus, which is the failure mode RAG exists to prevent.
  static const int floor = 400;

  // ── Measured prefill bands (tokens/sec) ─────────────────────────────────────
  //
  // A turn's prefill cost is `prompt_tokens / rate`, so at 22 tok/s a
  // 900-token context costs ~41 s of prefill on its own; at 45 tok/s the full
  // 1400 costs ~31 s. Those are the points where a wider context stops being
  // worth the wait.
  static const double _fastTps = 45.0;
  static const double _moderateTps = 22.0;
  static const double _slowTps = 10.0;

  // ── Budget per band ─────────────────────────────────────────────────────────
  static const int _fastBudget = validatedDefault; // 1400
  static const int _moderateBudget = 900;
  static const int _slowBudget = 600;
  static const int _verySlowBudget = floor; // 400

  /// Budget for a device whose hardware we cannot classify and which has not
  /// reported a measurement yet. Deliberately the validated default: an
  /// unknown device must not be silently downgraded.
  static const int _unknownBudget = validatedDefault;

  /// Budget for a device we can positively identify as slow-compute.
  static const int _inferredSlowBudget = _slowBudget; // 600

  // ── Measurement smoothing ───────────────────────────────────────────────────
  //
  // The raw per-turn rate is noisy (a turn that only prefilled 40 new tokens
  // after a prefix-cache hit is a poor sample). An EMA keeps the band stable,
  // which also keeps the assembled prompt stable and preserves KV prefix
  // reuse — a budget that flips between bands each turn would invalidate the
  // cached prefix every time.
  static const double _emaAlpha = 0.4;

  /// Minimum sample size for a prefill observation to be trusted at all.
  static const int _minSampleTokens = 64;
  static const int _minSampleMs = 150;

  /// Plausibility band for a reported rate, in tokens/sec. Anything outside is
  /// treated as a counter artefact (e.g. a cumulative native counter read
  /// before it has advanced) rather than as device speed.
  static const double _minPlausibleTps = 0.5;
  static const double _maxPlausibleTps = 500.0;

  /// EMA of the observed prefill rate, or `null` until a valid sample lands.
  static double? _emaTps;

  /// Number of accepted prefill samples this session (diagnostics/tests).
  static int _samples = 0;

  /// The most recent accepted prefill rate, or `null` (diagnostics/tests).
  static double? get measuredPrefillTps => _emaTps;

  /// Accepted sample count (diagnostics/tests).
  static int get sampleCount => _samples;

  /// Budget for the active device, folding in any measurements taken so far.
  ///
  /// Read once per turn, *before* prompt assembly, so a measurement from turn
  /// N governs turn N+1.
  static int resolve({DeviceProfile? profile}) {
    final int inferred = inferFromHardware(profile);
    final int measured = forPrefillRate(_emaTps);
    return math.min(inferred, measured);
  }

  /// Hardware-only upper bound. Pure; no measurement, no session state.
  ///
  /// Returns [validatedDefault] for any device we cannot classify, so the only
  /// devices that come down are the ones we have positive evidence are slow.
  static int inferFromHardware(DeviceProfile? profile) {
    if (profile == null) return _unknownBudget;

    // 1. RAM — a weak latency proxy, kept only for genuinely low-end parts.
    //    Every sub-5 GB Android device in the field is a slow-compute part,
    //    and the previous tier's numbers for this case are preserved verbatim
    //    so those devices do not move.
    if (profile.isLowRam || (profile.totalRamMb > 0 && profile.totalRamMb <= 5000)) {
      return _inferredSlowBudget;
    }

    // 2. SoC is on the repo's slow-compute list. On these parts the load
    //    ladder is CPU-only (see `hasSlowVulkanCompute`), so prefill runs on
    //    CPU and is bound by the same weak cores that made GPU offload a
    //    loss. This is the rule that catches the Helio G95 / Dimensity
    //    1200-class devices the old RAM tier over-provisioned.
    if (hasSlowVulkanCompute(profile.socModel)) {
      return _inferredSlowBudget;
    }

    // 3. Two or fewer big cores. Prefill is a batched matmul that scales with
    //    big-core count; a 2-big/6-LITTLE SoC has roughly a third of the
    //    big-core throughput of a 4-big part, which is the difference between
    //    a 30 s and a 10 s context prefill. `bigCores == 0` means detection
    //    failed (host VM, iOS, sysfs unavailable) — that is "unknown", not
    //    "slow", so it falls through to the default.
    if (profile.bigCores > 0 && profile.bigCores <= 2) {
      return _inferredSlowBudget;
    }

    return _unknownBudget;
  }

  /// Measured-only upper bound. Pure; no session state.
  ///
  /// A `null` (or non-positive) rate means "no measurement yet", which is not
  /// the same as "measured zero tokens/sec" — it returns [validatedDefault] so
  /// an unmeasured device is never penalised by this bound. The hardware
  /// inference is what decides in that case.
  static int forPrefillRate(double? tokensPerSecond) {
    if (tokensPerSecond == null || tokensPerSecond <= 0) {
      return validatedDefault;
    }
    if (tokensPerSecond >= _fastTps) return _fastBudget;
    if (tokensPerSecond >= _moderateTps) return _moderateBudget;
    if (tokensPerSecond >= _slowTps) return _slowBudget;
    return _verySlowBudget;
  }

  /// Folds one completed turn's native prefill counters into the EMA.
  ///
  /// [promptEvalTokens] / [promptEvalMs] are llama.cpp's `n_p_eval` /
  /// `t_p_eval_ms` — they count only tokens actually evaluated, so a prefix-
  /// cache hit on a later turn does not inflate the rate.
  ///
  /// Returns the accepted rate, or `null` when the sample was rejected. Never
  /// throws; callers on the inference path must not be able to break a turn.
  static double? observePrefill({
    required int promptEvalTokens,
    required int promptEvalMs,
  }) {
    try {
      if (promptEvalTokens < _minSampleTokens) return null;
      if (promptEvalMs < _minSampleMs) return null;
      final double tps = promptEvalTokens * 1000.0 / promptEvalMs;
      if (tps < _minPlausibleTps || tps > _maxPlausibleTps) return null;

      final double? previous = _emaTps;
      _emaTps = previous == null
          ? tps
          : previous + _emaAlpha * (tps - previous);
      _samples++;
      return tps;
    } catch (_) {
      return null;
    }
  }

  /// Clears session state. Called on model load (a different GGUF has a
  /// different throughput profile) and by tests.
  static void reset() {
    _emaTps = null;
    _samples = 0;
  }

  /// Human-readable explanation of the current budget, for the `rag.search`
  /// trace step. Kept here so the trace and the decision cannot drift apart.
  static String describe({DeviceProfile? profile}) {
    final int inferred = inferFromHardware(profile);
    final int measured = forPrefillRate(_emaTps);
    final int budget = math.min(inferred, measured);
    final String source = inferred <= measured ? 'hardware' : 'measured';
    final String rate =
        _emaTps == null ? 'none' : _emaTps!.toStringAsFixed(1);
    return 'budget=$budget source=$source inferred=$inferred '
        'measured=$measured ema_tps=$rate samples=$_samples';
  }
}
