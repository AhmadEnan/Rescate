import 'dart:math' as math;

List<double> magnitudeSpectrum(List<double> x) {
  final int n = _nextPow2(x.length);
  final List<double> out = <double>[];
  for (int k = 0; k <= n ~/ 2; k++) {
    double re = 0;
    double im = 0;
    for (int i = 0; i < n; i++) {
      final double sample = i < x.length ? x[i] : 0;
      final double angle = -2 * math.pi * k * i / n;
      re += sample * math.cos(angle);
      im += sample * math.sin(angle);
    }
    out.add(math.sqrt((re * re) + (im * im)) / n);
  }
  return out;
}

double dominantFrequency(
  List<double> x,
  double fs, {
  required double lowHz,
  required double highHz,
}) {
  if (x.isEmpty) {
    return 0;
  }
  final int n = _nextPow2(x.length);
  final List<double> spectrum = magnitudeSpectrum(_windowed(x));
  double bestFreq = 0;
  double bestMag = -1;
  for (int k = 1; k < spectrum.length; k++) {
    final double freq = k * fs / n;
    if (freq < lowHz || freq > highHz) {
      continue;
    }
    if (spectrum[k] > bestMag) {
      bestMag = spectrum[k];
      bestFreq = freq;
    }
  }
  return bestFreq;
}

List<double> _windowed(List<double> x) {
  if (x.length < 2) {
    return x;
  }
  return <double>[
    for (int i = 0; i < x.length; i++)
      x[i] * (0.5 - (0.5 * math.cos(2 * math.pi * i / (x.length - 1)))),
  ];
}

int _nextPow2(int n) {
  int out = 1;
  while (out < n) {
    out <<= 1;
  }
  return out;
}
