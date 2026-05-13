import 'dart:math' as math;

class Peak {
  const Peak({required this.index, required this.prominence});

  final int index;
  final double prominence;
}

List<Peak> detectPeaks(
  List<double> x, {
  required int minDistance,
  required double prominenceThresholdMad,
}) {
  if (x.length < 3) {
    return const <Peak>[];
  }
  final double med = _median(x);
  final double mad = _median(
    x.map((double v) => (v - med).abs()).toList(growable: false),
  );
  final double threshold = med + (prominenceThresholdMad * math.max(mad, 1e-9));
  final List<Peak> candidates = <Peak>[];
  for (int i = 1; i < x.length - 1; i++) {
    if (x[i] > x[i - 1] && x[i] >= x[i + 1] && x[i] > threshold) {
      final int left = math.max(0, i - minDistance);
      final int right = math.min(x.length - 1, i + minDistance);
      final double baseline = math.max(
        x.sublist(left, i + 1).reduce(math.min),
        x.sublist(i, right + 1).reduce(math.min),
      );
      candidates.add(Peak(index: i, prominence: x[i] - baseline));
    }
  }
  candidates.sort((Peak a, Peak b) => b.prominence.compareTo(a.prominence));
  final List<Peak> accepted = <Peak>[];
  for (final Peak peak in candidates) {
    final bool farEnough = accepted.every(
      (Peak other) => (other.index - peak.index).abs() >= minDistance,
    );
    if (farEnough) {
      accepted.add(peak);
    }
  }
  accepted.sort((Peak a, Peak b) => a.index.compareTo(b.index));
  return accepted;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final int mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}
