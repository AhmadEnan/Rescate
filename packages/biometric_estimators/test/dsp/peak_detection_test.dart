import 'dart:math' as math;

import 'package:biometric_estimators/src/dsp/peak_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detectPeaks finds a 1 Hz synthetic waveform', () {
    const double fs = 100;
    final List<double> signal = <double>[
      for (int i = 0; i < 1000; i++) math.sin(2 * math.pi * i / fs),
    ];
    final List<Peak> peaks = detectPeaks(
      signal,
      minDistance: 60,
      prominenceThresholdMad: 0.2,
    );
    expect(peaks.length, inInclusiveRange(9, 11));
  });
}
