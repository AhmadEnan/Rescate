import 'dart:math' as math;

import 'fft.dart';

class WelchResult {
  const WelchResult({required this.freqs, required this.psd});

  final List<double> freqs;
  final List<double> psd;
}

WelchResult welchPeriodogram(
  List<double> signal,
  double fs, {
  required int windowLength,
  double overlapFraction = 0.5,
}) {
  if (signal.isEmpty || windowLength <= 0) {
    return const WelchResult(freqs: <double>[], psd: <double>[]);
  }
  final int step = math.max(1, (windowLength * (1 - overlapFraction)).round());
  final List<double> sum = <double>[];
  int segments = 0;
  for (int start = 0; start + windowLength <= signal.length; start += step) {
    final List<double> window = signal.sublist(start, start + windowLength);
    final List<double> spectrum = magnitudeSpectrum(window);
    if (sum.isEmpty) {
      sum.addAll(List<double>.filled(spectrum.length, 0));
    }
    for (int i = 0; i < spectrum.length; i++) {
      sum[i] += spectrum[i] * spectrum[i];
    }
    segments++;
  }
  if (segments == 0) {
    final List<double> spectrum = magnitudeSpectrum(signal);
    sum.addAll(spectrum.map((double value) => value * value));
    segments = 1;
  }
  final List<double> psd = sum
      .map((double value) => value / segments)
      .toList(growable: false);
  final int n = (psd.length - 1) * 2;
  final List<double> freqs = <double>[
    for (int i = 0; i < psd.length; i++) i * fs / n,
  ];
  return WelchResult(freqs: freqs, psd: psd);
}
