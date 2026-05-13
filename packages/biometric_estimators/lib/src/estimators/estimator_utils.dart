import 'dart:async';
import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import '../core/diagnostic_event.dart';
import '../core/signal_quality.dart';
import '../dsp/filters.dart';
import '../dsp/fft.dart';
import '../dsp/peak_detection.dart';

BiometricMeasurement buildMeasurement({
  required BiometricId id,
  required DateTime capturedAt,
  required Duration duration,
  required MeasurementStatus status,
  required double confidence,
  required ScalarReading? primary,
  List<ScalarReading> secondary = const <ScalarReading>[],
  List<String> qualityFlags = const <String>[],
  Map<String, dynamic>? extras,
  List<SensorId>? sourceSensors,
  String? methodology,
}) {
  final BiometricDescriptor descriptor = biometricDescriptorFor(id);
  return BiometricMeasurement(
    id: id,
    capturedAt: capturedAt,
    duration: duration,
    status: status,
    confidence: confidence,
    primary: primary,
    secondary: secondary,
    qualityFlags: qualityFlags,
    sourceSensors: sourceSensors ?? descriptor.sourceSensors,
    methodology: methodology ?? descriptor.methodology,
    biomarker: descriptor.biomarker,
    application: descriptor.application,
    displayName: descriptor.displayName,
    extras: extras,
  );
}

bool hasAnySensor(
  SensorAvailabilityService availability,
  Iterable<SensorId> ids,
) {
  return ids.any((SensorId id) {
    final SensorStatus status = availability.get(id).status;
    return status == SensorStatus.available ||
        status == SensorStatus.needsPermission;
  });
}

double sampleRateFromCount(int count, Duration duration, double fallbackHz) {
  final int elapsedMs = duration.inMilliseconds;
  if (count < 2 || elapsedMs <= 0) {
    return fallbackHz;
  }
  final double computed = count * 1000 / elapsedMs;
  // If the computed rate is vastly higher than expected (e.g. >10x),
  // this is likely a test stream that drained synchronously or very quickly.
  if (computed > fallbackHz * 10) {
    return fallbackHz;
  }
  return computed;
}

/// Collects events from [stream] for [duration], emitting progress via [session].
/// [onRawSample] is called for every collected event and can be used to forward
/// samples to [CaptureSession.emitRawSample] for live display.
Future<List<T>> collectWindow<T>(
  Stream<T> stream,
  Duration duration,
  CaptureSession session, {
  void Function(T)? onRawSample,
}) async {
  final List<T> out = <T>[];
  final Completer<void> done = Completer<void>();
  late final StreamSubscription<T> sub;
  final Stopwatch sw = Stopwatch()..start();
  sub = stream.listen(
    (T event) {
      out.add(event);
      onRawSample?.call(event);
      session.emitProgress(sw.elapsedMilliseconds / duration.inMilliseconds);
      if (sw.elapsed >= duration && !done.isCompleted) {
        done.complete();
      }
    },
    onError: done.completeError,
    onDone: () {
      if (!done.isCompleted) {
        done.complete();
      }
    },
  );
  await Future.any(<Future<void>>[
    done.future,
    Future<void>.delayed(duration),
    session.cancelToken,
  ]);
  await sub.cancel();
  session.emitProgress(1);
  return out;
}

MeasurementStatus statusFromConfidence(double confidence) {
  if (confidence >= 0.6) {
    return MeasurementStatus.ok;
  }
  if (confidence >= 0.3) {
    return MeasurementStatus.lowConfidence;
  }
  return MeasurementStatus.failed;
}

List<double> detrendMovingAverage(List<double> xs, int radius) {
  if (xs.isEmpty || radius <= 0) {
    return xs;
  }
  return <double>[
    for (int i = 0; i < xs.length; i++) xs[i] - _meanWindow(xs, i, radius),
  ];
}

List<double> rollingRms(List<double> xs, int radius) {
  if (xs.isEmpty) {
    return const <double>[];
  }
  return <double>[
    for (int i = 0; i < xs.length; i++)
      math.sqrt(
        _window(xs, i, radius)
                .map((double value) => value * value)
                .reduce((double a, double b) => a + b) /
            _window(xs, i, radius).length,
      ),
  ];
}

List<double> ibisFromPeaks(List<Peak> peaks, double fs) {
  final List<double> ibis = <double>[];
  for (int i = 1; i < peaks.length; i++) {
    ibis.add((peaks[i].index - peaks[i - 1].index) * 1000 / fs);
  }
  return ibis;
}

double heartRateFromIbis(List<double> ibis) {
  if (ibis.isEmpty) {
    return 0;
  }
  final double meanIbi =
      ibis.reduce((double a, double b) => a + b) / ibis.length;
  return 60000 / meanIbi;
}

double rmssd(List<double> ibis) {
  if (ibis.length < 2) {
    return 0;
  }
  final List<double> diffs = <double>[
    for (int i = 1; i < ibis.length; i++) ibis[i] - ibis[i - 1],
  ];
  final double meanSq =
      diffs
          .map((double value) => value * value)
          .reduce((double a, double b) => a + b) /
      diffs.length;
  return math.sqrt(meanSq);
}

double stdDev(List<double> xs) {
  if (xs.length < 2) {
    return 0;
  }
  final double mean = xs.reduce((double a, double b) => a + b) / xs.length;
  final double variance =
      xs
          .map((double value) => math.pow(value - mean, 2).toDouble())
          .reduce((double a, double b) => a + b) /
      xs.length;
  return math.sqrt(variance);
}

BiometricMeasurement cardiovascularFromSignal({
  required BiometricId id,
  required DateTime capturedAt,
  required Duration duration,
  required List<double> signal,
  required double fs,
  required double lowHz,
  required double highHz,
  required int minDistance,
  required String secondaryLabel,
  Map<String, dynamic>? extras,
  List<String> qualityFlags = const <String>[],
  double prominenceThresholdMad = 2.0,
  // Seconds to discard at the start to skip the physical settling transient
  // (e.g. the phone being placed on the chest).
  double warmupSeconds = 0.0,
  // Pass the active session to receive stage-by-stage diagnostic events.
  CaptureSession? session,
}) {
  // ── Stage 0: warmup drop ────────────────────────────────────────────────
  final int warmupSamples =
      (warmupSeconds * fs).round().clamp(0, signal.length);
  final List<double> settled =
      warmupSamples > 0 ? signal.sublist(warmupSamples) : signal;

  _diag(
    session,
    'collection',
    '${signal.length} samples @ ~${fs.toStringAsFixed(0)} Hz'
    '  (${(signal.length / fs).toStringAsFixed(1)} s)',
  );

  if (warmupSamples > 0) {
    _diag(
      session,
      'warmup',
      'Dropped $warmupSamples samples (${warmupSeconds.toStringAsFixed(1)} s)'
          ' to skip settling transient — ${settled.length} remain',
    );
  }

  // ── Stage 1: raw signal stats ───────────────────────────────────────────
  final double rawRms = _rms(settled);
  final double rawPeak =
      settled.isEmpty ? 0 : settled.map((double v) => v.abs()).reduce(math.max);
  _diag(
    session,
    'raw signal',
    'RMS ${rawRms.toStringAsFixed(5)}'
        '  peak-abs ${rawPeak.toStringAsFixed(5)}',
    rawRms < 1e-6 ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
  );

  // ── Stage 2: detrend ────────────────────────────────────────────────────
  final List<double> clean = detrendMovingAverage(settled, fs.round());
  final double cleanRms = _rms(clean);
  _diag(session, 'detrend', 'After moving-avg detrend  RMS ${cleanRms.toStringAsFixed(5)}');

  // ── Stage 3: band-pass filter ───────────────────────────────────────────
  final double nyquistSafeHighHz = math.min(
    highHz,
    (fs * 0.45).clamp(lowHz, highHz),
  );
  final List<double> filtered = Butterworth.bandPass(
    4,
    lowHz,
    nyquistSafeHighHz,
    fs,
  ).processAll(clean);
  final double filtRms = _rms(filtered);
  final double filtPeak =
      filtered.isEmpty
          ? 0
          : filtered.map((double v) => v.abs()).reduce(math.max);
  _diag(
    session,
    'band-pass',
    '$lowHz–${nyquistSafeHighHz.toStringAsFixed(1)} Hz'
        '  RMS ${filtRms.toStringAsFixed(5)}'
        '  peak ${filtPeak.toStringAsFixed(5)}',
    filtRms < 1e-7 ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
  );

  // ── Stage 4: peak detection ─────────────────────────────────────────────
  final List<Peak> peaks = detectPeaks(
    filtered,
    minDistance: minDistance,
    prominenceThresholdMad: prominenceThresholdMad,
  );
  _diag(
    session,
    'peaks',
    peaks.isEmpty
        ? 'No peaks detected — signal may be too weak or noisy'
            ' (try stricter placement)'
        : '${peaks.length} peaks  min-dist $minDistance samples'
            '  MAD×$prominenceThresholdMad',
    peaks.isEmpty ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
  );

  // ── Stage 5: IBI computation ────────────────────────────────────────────
  final List<double> rawIbis = ibisFromPeaks(peaks, fs);
  final List<double> ibis = rawIbis
      .where((double ibi) => ibi >= 300 && ibi <= 2000)
      .toList(growable: false);
  final double ibiHr = heartRateFromIbis(ibis);
  final double meanIbiMs =
      ibis.isEmpty
          ? 0
          : ibis.reduce((double a, double b) => a + b) / ibis.length;
  _diag(
    session,
    'IBIs',
    rawIbis.isEmpty
        ? 'No IBIs (no peaks to diff)'
        : '${rawIbis.length} raw → ${ibis.length} valid [300–2000 ms]'
            '  mean ${meanIbiMs.toStringAsFixed(0)} ms'
            ' → HR ${ibiHr.toStringAsFixed(1)} bpm',
    ibis.isEmpty ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
  );

  // ── Stage 6: frequency fallback ─────────────────────────────────────────
  final double frequencyHr =
      dominantFrequency(filtered, fs, lowHz: lowHz, highHz: highHz) * 60;
  final double hr = ibiHr > 0 ? ibiHr : frequencyHr;
  if (ibiHr <= 0) {
    _diag(
      session,
      'freq fallback',
      frequencyHr > 0
          ? 'No IBI path — using FFT dominant freq:'
              ' ${(frequencyHr / 60).toStringAsFixed(3)} Hz'
              ' → ${frequencyHr.toStringAsFixed(1)} bpm'
          : 'No dominant frequency found in $lowHz–$highHz Hz band',
      frequencyHr > 0 ? DiagnosticSeverity.info : DiagnosticSeverity.warning,
    );
  }

  // ── Stage 7: confidence ─────────────────────────────────────────────────
  final double sigRms = _rms(filtered);
  final List<double> normProminences =
      sigRms > 0
          ? peaks
              .map((Peak p) => p.prominence / sigRms)
              .toList(growable: false)
          : peaks.map((Peak p) => p.prominence).toList(growable: false);
  final double peakConf = confidenceFromPeakProminence(normProminences);
  final double ibiConf = confidenceFromIbiVariability(ibis);
  final double peakConfidence = math.min(peakConf, ibiConf);
  final double confidence =
      ibiHr > 0 ? peakConfidence : (frequencyHr > 0 ? 0.72 : 0.0);
  final MeasurementStatus status = statusFromConfidence(confidence);
  _diag(
    session,
    'confidence',
    'peak_norm=${peakConf.toStringAsFixed(2)}'
        '  ibi_var=${ibiConf.toStringAsFixed(2)}'
        '  final=${confidence.toStringAsFixed(2)}'
        ' → ${status.name}',
    status == MeasurementStatus.failed
        ? DiagnosticSeverity.error
        : DiagnosticSeverity.info,
  );

  final double secondary = secondaryLabel == 'rmssd' ? rmssd(ibis) : stdDev(ibis);
  return buildMeasurement(
    id: id,
    capturedAt: capturedAt,
    duration: duration,
    status: status,
    confidence: confidence,
    primary: hr > 0
        ? ScalarReading(label: 'heart_rate', value: hr, unit: 'bpm')
        : null,
    secondary: <ScalarReading>[
      ScalarReading(label: secondaryLabel, value: secondary, unit: 'ms'),
      ScalarReading(
        label: 'ibi_count',
        value: ibis.length.toDouble(),
        unit: 'count',
      ),
    ],
    qualityFlags: qualityFlags,
    extras: <String, dynamic>{
      'sample_rate_hz': fs,
      'samples_used': settled.length,
      'warmup_dropped': warmupSamples,
      ...?extras,
    },
  );
}

void _diag(
  CaptureSession? session,
  String stage,
  String message, [
  DiagnosticSeverity level = DiagnosticSeverity.info,
]) {
  session?.emitDiagnostic(
    DiagnosticEvent(stage: stage, message: message, level: level),
  );
}

double _meanWindow(List<double> xs, int center, int radius) {
  final List<double> win = _window(xs, center, radius);
  return win.reduce((double a, double b) => a + b) / win.length;
}

List<double> _window(List<double> xs, int center, int radius) {
  final int start = math.max(0, center - radius);
  final int end = math.min(xs.length, center + radius + 1);
  return xs.sublist(start, end);
}

double _rms(List<double> xs) {
  if (xs.isEmpty) {
    return 0;
  }
  final double sumSq =
      xs.map((double v) => v * v).reduce((double a, double b) => a + b);
  return math.sqrt(sumSq / xs.length);
}
