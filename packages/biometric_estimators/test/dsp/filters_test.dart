import 'dart:math' as math;

import 'package:biometric_estimators/src/dsp/filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('band-pass keeps 1 Hz and attenuates 5 Hz', () {
    const double fs = 100;
    final List<double> oneHz = <double>[
      for (int i = 0; i < 1000; i++) math.sin(2 * math.pi * i / fs),
    ];
    final List<double> fiveHz = <double>[
      for (int i = 0; i < 1000; i++) math.sin(2 * math.pi * 5 * i / fs),
    ];
    final double pass = _rms(
      Butterworth.bandPass(4, 0.5, 4, fs).processAll(oneHz),
    );
    final double stop = _rms(
      Butterworth.bandPass(4, 0.5, 4, fs).processAll(fiveHz),
    );
    expect(20 * math.log(pass / stop) / math.ln10, greaterThan(8));
  });
}

double _rms(List<double> xs) {
  return math.sqrt(
    xs.map((double v) => v * v).reduce((double a, double b) => a + b) /
        xs.length,
  );
}
