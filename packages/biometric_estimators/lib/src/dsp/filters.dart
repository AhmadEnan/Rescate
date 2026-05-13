import 'dart:math' as math;

class Biquad {
  Biquad({
    required double b0,
    required double b1,
    required double b2,
    required double a0,
    required double a1,
    required double a2,
  }) : _b0 = b0 / a0,
       _b1 = b1 / a0,
       _b2 = b2 / a0,
       _a1 = a1 / a0,
       _a2 = a2 / a0;

  final double _b0;
  final double _b1;
  final double _b2;
  final double _a1;
  final double _a2;
  double _z1 = 0;
  double _z2 = 0;

  double process(double sample) {
    final double out = (_b0 * sample) + _z1;
    _z1 = (_b1 * sample) - (_a1 * out) + _z2;
    _z2 = (_b2 * sample) - (_a2 * out);
    return out;
  }
}

class BiquadCascade {
  BiquadCascade(this._sections);

  final List<Biquad> _sections;

  double process(double sample) {
    double y = sample;
    for (final Biquad section in _sections) {
      y = section.process(y);
    }
    return y;
  }

  List<double> processAll(List<double> xs) {
    return xs.map(process).toList(growable: false);
  }
}

class Butterworth {
  const Butterworth._();

  static BiquadCascade lowPass(int order, double cutoffHz, double fs) {
    final int sections = math.max(1, order);
    return BiquadCascade(<Biquad>[
      for (int i = 0; i < sections; i++)
        _lowPass(cutoffHz, fs, _qFor(i, sections)),
    ]);
  }

  static BiquadCascade highPass(int order, double cutoffHz, double fs) {
    final int sections = math.max(1, order);
    return BiquadCascade(<Biquad>[
      for (int i = 0; i < sections; i++)
        _highPass(cutoffHz, fs, _qFor(i, sections)),
    ]);
  }

  static BiquadCascade bandPass(
    int order,
    double lowHz,
    double highHz,
    double fs,
  ) {
    final int sections = math.max(1, order);
    return BiquadCascade(<Biquad>[
      for (int i = 0; i < sections; i++)
        _highPass(lowHz, fs, _qFor(i, sections)),
      for (int i = 0; i < sections; i++)
        _lowPass(highHz, fs, _qFor(i, sections)),
    ]);
  }

  static double _qFor(int section, int sections) {
    final double theta = math.pi * (2 * section + 1) / (4 * sections);
    return 1.0 / (2.0 * math.cos(theta)).clamp(0.45, 1.6);
  }

  static Biquad _lowPass(double cutoffHz, double fs, double q) {
    final double w0 = 2 * math.pi * cutoffHz / fs;
    final double cosW0 = math.cos(w0);
    final double alpha = math.sin(w0) / (2 * q);
    return Biquad(
      b0: (1 - cosW0) / 2,
      b1: 1 - cosW0,
      b2: (1 - cosW0) / 2,
      a0: 1 + alpha,
      a1: -2 * cosW0,
      a2: 1 - alpha,
    );
  }

  static Biquad _highPass(double cutoffHz, double fs, double q) {
    final double w0 = 2 * math.pi * cutoffHz / fs;
    final double cosW0 = math.cos(w0);
    final double alpha = math.sin(w0) / (2 * q);
    return Biquad(
      b0: (1 + cosW0) / 2,
      b1: -(1 + cosW0),
      b2: (1 + cosW0) / 2,
      a0: 1 + alpha,
      a1: -2 * cosW0,
      a2: 1 - alpha,
    );
  }
}
