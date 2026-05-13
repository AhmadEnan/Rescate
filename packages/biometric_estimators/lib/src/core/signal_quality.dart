import 'dart:math' as math;

double confidenceFromPeakProminence(List<double> prominences) {
  if (prominences.isEmpty) {
    return 0.0;
  }
  final double mean =
      prominences.reduce((double a, double b) => a + b) / prominences.length;
  return (mean / (mean + 0.35)).clamp(0.0, 1.0);
}

double confidenceFromIbiVariability(List<double> ibisMs) {
  if (ibisMs.length < 3) {
    return 0.0;
  }
  final double mean =
      ibisMs.reduce((double a, double b) => a + b) / ibisMs.length;
  if (mean <= 0) {
    return 0.0;
  }
  final double variance =
      ibisMs
          .map((double ibi) => math.pow(ibi - mean, 2).toDouble())
          .reduce((double a, double b) => a + b) /
      ibisMs.length;
  final double cv = math.sqrt(variance) / mean;
  return (1.0 - (cv / 0.25)).clamp(0.0, 1.0);
}

double confidenceFromSnr(double snrDb) {
  return ((snrDb + 5.0) / 25.0).clamp(0.0, 1.0);
}
