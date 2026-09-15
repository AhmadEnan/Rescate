// packages/ai_inference/test/context_budget_test.dart

import 'package:ai_inference/ai_inference.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal [DeviceProfile] builder. Only the fields the budget reads are
/// interesting, so the rest are fixed at plausible mid-range values.
DeviceProfile profile({
  int totalRamMb = 12000,
  bool isLowRam = false,
  int bigCores = 4,
  int cores = 8,
  String socModel = 'SM8550',
}) {
  return DeviceProfile(
    cores: cores,
    bigCores: bigCores,
    recommendedThreads: bigCores == 0 ? 6 : bigCores,
    recommendedBatchThreads: 6,
    totalRamMb: totalRamMb,
    availRamMb: totalRamMb ~/ 2,
    isLowRam: isLowRam,
    recommendedGpuLayers: 999,
    recommendedContextSize: isLowRam ? 2048 : 4096,
    recommendedBatchSize: 256,
    recommendedMicroBatchSize: 128,
    cacheTypeK: isLowRam ? 'q8_0' : 'f16',
    cacheTypeV: isLowRam ? 'q8_0' : 'f16',
    socModel: socModel,
  );
}

void main() {
  setUp(RagContextBudget.reset);
  tearDown(RagContextBudget.reset);

  group('inferFromHardware', () {
    test('unknown profile is not penalised', () {
      expect(RagContextBudget.inferFromHardware(null),
          RagContextBudget.validatedDefault);
    });

    test('device we cannot classify keeps the validated default', () {
      // Empty SoC string (iOS / host VM), big-core detection failed (0),
      // plenty of RAM: nothing here is evidence of slowness.
      expect(
        RagContextBudget.inferFromHardware(
          profile(totalRamMb: 12000, bigCores: 0, socModel: ''),
        ),
        RagContextBudget.validatedDefault,
      );
    });

    test('low-RAM flag tightens the budget', () {
      expect(
        RagContextBudget.inferFromHardware(profile(isLowRam: true)),
        600,
      );
    });

    test('small total RAM tightens the budget', () {
      expect(RagContextBudget.inferFromHardware(profile(totalRamMb: 4000)), 600);
      expect(RagContextBudget.inferFromHardware(profile(totalRamMb: 5000)), 600);
      expect(RagContextBudget.inferFromHardware(profile(totalRamMb: 6000)),
          RagContextBudget.validatedDefault);
    });

    test('unknown RAM (0) does not trip the low-RAM rule', () {
      // totalRamMb == 0 means "detection failed", not "no memory".
      expect(
        RagContextBudget.inferFromHardware(
          profile(totalRamMb: 0, bigCores: 4, socModel: 'SM8550'),
        ),
        RagContextBudget.validatedDefault,
      );
    });

    // ── The regression this whole file exists for ────────────────────────────
    test('8 GB Helio G95 (MT6785) gets a tight budget, not the largest one', () {
      // Real device: realme 7, MemTotal 7,835,204 kB -> 7651 MiB. The old
      // RAM-only tier cleared its 7500 bar and handed this 2020 mid-ranger the
      // 1400-token budget while a 4 GB 2023 part got 600. RAM is capacity;
      // prefill cost is compute.
      final int budget = RagContextBudget.inferFromHardware(
        profile(totalRamMb: 7651, bigCores: 2, socModel: 'MT6785'),
      );
      expect(budget, 600);
      expect(budget, lessThan(RagContextBudget.validatedDefault));
    });

    test('every SoC on the slow-compute list is tightened', () {
      for (final soc in slowVulkanSocMarkers) {
        expect(
          RagContextBudget.inferFromHardware(
            profile(totalRamMb: 12000, bigCores: 4, socModel: soc),
          ),
          600,
          reason: '$soc is a known slow-compute part',
        );
      }
    });

    test('SoC matching is case-insensitive', () {
      expect(
        RagContextBudget.inferFromHardware(profile(socModel: 'mt6785')),
        600,
      );
    });

    test('two big cores tighten the budget even on an unlisted SoC', () {
      expect(
        RagContextBudget.inferFromHardware(
          profile(bigCores: 2, socModel: 'SM6375'),
        ),
        600,
      );
    });

    test('a modern 4-big-core flagship keeps the full budget', () {
      // The friend's higher-end demo phone must not be penalised.
      expect(
        RagContextBudget.inferFromHardware(
          profile(totalRamMb: 16000, bigCores: 4, socModel: 'SM8550'),
        ),
        RagContextBudget.validatedDefault,
      );
      expect(
        RagContextBudget.inferFromHardware(
          profile(totalRamMb: 12288, bigCores: 6, socModel: 'SM8650'),
        ),
        RagContextBudget.validatedDefault,
      );
    });
  });

  group('forPrefillRate', () {
    test('no measurement leaves the default intact', () {
      expect(RagContextBudget.forPrefillRate(null),
          RagContextBudget.validatedDefault);
      expect(RagContextBudget.forPrefillRate(0),
          RagContextBudget.validatedDefault);
    });

    test('band edges', () {
      expect(RagContextBudget.forPrefillRate(120), 1400);
      expect(RagContextBudget.forPrefillRate(45), 1400);
      expect(RagContextBudget.forPrefillRate(44.9), 900);
      expect(RagContextBudget.forPrefillRate(22), 900);
      expect(RagContextBudget.forPrefillRate(21.9), 600);
      expect(RagContextBudget.forPrefillRate(10), 600);
      expect(RagContextBudget.forPrefillRate(9.9), RagContextBudget.floor);
      expect(RagContextBudget.forPrefillRate(1), RagContextBudget.floor);
    });

    test('rate is monotone: a faster device never gets a smaller budget', () {
      // Starts at the lowest rate observePrefill will ever accept (0.5 tok/s);
      // 0 is "no measurement", not "infinitely slow" — see forPrefillRate.
      var previous = 0;
      for (var tps = 0.5; tps <= 200; tps += 0.5) {
        final int budget = RagContextBudget.forPrefillRate(tps);
        expect(budget, greaterThanOrEqualTo(previous),
            reason: 'at $tps tok/s the budget went backwards');
        previous = budget;
      }
      expect(previous, RagContextBudget.validatedDefault);
    });
  });

  group('resolve', () {
    test('without a measurement it equals the hardware inference', () {
      final p = profile(totalRamMb: 7651, bigCores: 2, socModel: 'MT6785');
      expect(RagContextBudget.resolve(profile: p),
          RagContextBudget.inferFromHardware(p));
    });

    test('a fast measurement cannot relax a slow-hardware verdict', () {
      // min(), never max(): a measurement that looks good on a part we have
      // positive evidence is slow must not hand back a bigger context.
      RagContextBudget.observePrefill(promptEvalTokens: 2000, promptEvalMs: 10000);
      expect(RagContextBudget.measuredPrefillTps, closeTo(200, 0.01));
      expect(
        RagContextBudget.resolve(
          profile: profile(totalRamMb: 7651, bigCores: 2, socModel: 'MT6785'),
        ),
        600,
      );
    });

    test('a slow measurement tightens an otherwise unclassified device', () {
      final p = profile(totalRamMb: 12000, bigCores: 8, socModel: 'SM8650');
      expect(RagContextBudget.resolve(profile: p),
          RagContextBudget.validatedDefault);

      RagContextBudget.observePrefill(promptEvalTokens: 100, promptEvalMs: 20000);
      expect(RagContextBudget.measuredPrefillTps, closeTo(5, 0.01));
      expect(RagContextBudget.resolve(profile: p), RagContextBudget.floor);
    });

    test('never exceeds the validated default and never drops below the floor',
        () {
      final profiles = <DeviceProfile>[
        profile(),
        profile(isLowRam: true, totalRamMb: 2000, bigCores: 0, socModel: ''),
        profile(totalRamMb: 0, bigCores: 0, socModel: ''),
        profile(totalRamMb: 7651, bigCores: 2, socModel: 'MT6785'),
      ];
      for (final p in profiles) {
        for (var tps = 0.0; tps <= 300; tps += 3) {
          RagContextBudget.reset();
          RagContextBudget.observePrefill(
            promptEvalTokens: (tps * 10).round().clamp(64, 1 << 30),
            promptEvalMs: 10000,
          );
          final int budget = RagContextBudget.resolve(profile: p);
          expect(budget, lessThanOrEqualTo(RagContextBudget.validatedDefault));
          expect(budget, greaterThanOrEqualTo(RagContextBudget.floor));
        }
      }
    });
  });

  group('observePrefill', () {
    test('rejects a sample that is too small to be meaningful', () {
      // A turn that only prefilled the new user text after a prefix-cache hit.
      expect(
        RagContextBudget.observePrefill(promptEvalTokens: 40, promptEvalMs: 3000),
        isNull,
      );
      expect(RagContextBudget.measuredPrefillTps, isNull);
      expect(RagContextBudget.sampleCount, 0);
    });

    test('rejects a sample with a degenerate duration', () {
      expect(
        RagContextBudget.observePrefill(promptEvalTokens: 500, promptEvalMs: 0),
        isNull,
      );
      expect(
        RagContextBudget.observePrefill(promptEvalTokens: 500, promptEvalMs: 100),
        isNull,
      );
      expect(RagContextBudget.measuredPrefillTps, isNull);
    });

    test('rejects an implausible rate as a counter artefact', () {
      // e.g. a cumulative native counter read before it advanced.
      expect(
        RagContextBudget.observePrefill(
          promptEvalTokens: 100000,
          promptEvalMs: 150,
        ),
        isNull,
      );
      expect(RagContextBudget.measuredPrefillTps, isNull);
    });

    test('accepts a plausible sample and seeds the EMA', () {
      final rate = RagContextBudget.observePrefill(
        promptEvalTokens: 600,
        promptEvalMs: 20000,
      );
      expect(rate, closeTo(30, 0.01));
      expect(RagContextBudget.measuredPrefillTps, closeTo(30, 0.01));
      expect(RagContextBudget.sampleCount, 1);
    });

    test('smooths across samples instead of following the last one', () {
      RagContextBudget.observePrefill(promptEvalTokens: 600, promptEvalMs: 20000);
      // alpha 0.4 -> 30 + 0.4 * (10 - 30) = 22
      RagContextBudget.observePrefill(promptEvalTokens: 200, promptEvalMs: 20000);
      expect(RagContextBudget.measuredPrefillTps, closeTo(22, 0.01));
      expect(RagContextBudget.sampleCount, 2);
    });

    test('a single outlier cannot move the band on its own', () {
      RagContextBudget.observePrefill(promptEvalTokens: 600, promptEvalMs: 20000);
      expect(RagContextBudget.resolve(profile: profile()), 900);
      // One very fast sample: 30 -> 30 + 0.4*(120-30) = 66
      RagContextBudget.observePrefill(promptEvalTokens: 1200, promptEvalMs: 10000);
      expect(RagContextBudget.measuredPrefillTps, closeTo(66, 0.01));
      // It does lift the band, but only after evidence — and never past the
      // hardware inference or the validated default.
      expect(
        RagContextBudget.resolve(profile: profile()),
        lessThanOrEqualTo(RagContextBudget.validatedDefault),
      );
    });

    test('reset clears the measurement', () {
      RagContextBudget.observePrefill(promptEvalTokens: 600, promptEvalMs: 20000);
      RagContextBudget.reset();
      expect(RagContextBudget.measuredPrefillTps, isNull);
      expect(RagContextBudget.sampleCount, 0);
      expect(RagContextBudget.resolve(profile: profile()),
          RagContextBudget.validatedDefault);
    });
  });

  group('describe', () {
    test('names the binding constraint and the measured rate', () {
      final p = profile(totalRamMb: 7651, bigCores: 2, socModel: 'MT6785');
      expect(
        RagContextBudget.describe(profile: p),
        'budget=600 source=hardware inferred=600 measured=1400 '
        'ema_tps=none samples=0',
      );

      RagContextBudget.observePrefill(promptEvalTokens: 100, promptEvalMs: 20000);
      expect(
        RagContextBudget.describe(profile: p),
        'budget=400 source=measured inferred=600 measured=400 '
        'ema_tps=5.0 samples=1',
      );
    });
  });
}
