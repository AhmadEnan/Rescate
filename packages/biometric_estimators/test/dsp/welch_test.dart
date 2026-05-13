import 'dart:math' as math;

import 'package:biometric_estimators/src/dsp/welch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Welch periodogram returns finite spectrum for white noise', () {
    final math.Random random = math.Random(4);
    final List<double> noise = <double>[
      for (int i = 0; i < 2048; i++) random.nextDouble() - 0.5,
    ];
    final WelchResult result = welchPeriodogram(noise, 100, windowLength: 256);
    expect(result.freqs.length, result.psd.length);
    expect(result.psd.every((double value) => value.isFinite), isTrue);
  });
}
