import 'dart:math' as math;

import 'package:biometric_estimators/src/dsp/fft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dominantFrequency detects a sine tone', () {
    const double fs = 100;
    final List<double> signal = <double>[
      for (int i = 0; i < 1000; i++) math.sin(2 * math.pi * 1.2 * i / fs),
    ];
    expect(
      dominantFrequency(signal, fs, lowHz: 0.5, highHz: 3),
      closeTo(1.2, 0.05),
    );
  });
}
