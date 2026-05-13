import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/mic_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import '../core/diagnostic_event.dart';
import '../dsp/filters.dart';
import '../dsp/welch.dart';
import 'estimator_utils.dart';

class AcousticRespirationEstimator implements BiometricEstimator {
  AcousticRespirationEstimator({MicSource? source})
    : _source = source ?? MicSource();

  final MicSource _source;

  @override
  BiometricId get id => BiometricId.acousticRespiration;

  @override
  Duration get suggestedDuration => const Duration(seconds: 60);

  @override
  String get captureInstruction =>
      'Hold the phone near the chest or mouth and breathe normally.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[
      SensorId.memsMicrophone,
    ]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();

    final List<double> samples = await _source.samples(
      duration: suggestedDuration,
      onProgress: session.emitProgress,
      cancelToken: session.cancelToken,
    );
    session.emitProgress(1);

    if (session.isCancelled || samples.isEmpty) {
      return buildMeasurement(
        id: id,
        capturedAt: started,
        duration: DateTime.now().difference(started),
        status: MeasurementStatus.failed,
        confidence: 0,
        primary: null,
      );
    }

    session.emitDiagnostic(DiagnosticEvent(
      stage: 'collection',
      message: '${samples.length} samples @ 16000 Hz'
          '  (${(samples.length / 16000).toStringAsFixed(1)} s)',
    ));

    // ── Stage 1: full-wave rectify ─────────────────────────────────────────
    final List<double> rectified = samples
        .map((double value) => value.abs())
        .toList(growable: false);
    final double rectRms = _rmsOf(rectified);
    session.emitDiagnostic(DiagnosticEvent(
      stage: 'rectify',
      message: 'Full-wave rectify  RMS ${rectRms.toStringAsFixed(5)}',
      level: rectRms < 1e-5 ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
    ));

    // ── Stage 2: low-pass envelope at 5 Hz ────────────────────────────────
    final List<double> envelope = Butterworth.lowPass(
      2,
      5,
      16000,
    ).processAll(rectified);

    // ── Stage 3: downsample to 50 Hz ──────────────────────────────────────
    const int step = 320; // 16000 / 50
    final List<double> downsampled = <double>[
      for (int i = 0; i < envelope.length; i += step) envelope[i],
    ];
    session.emitDiagnostic(DiagnosticEvent(
      stage: 'envelope',
      message: 'Low-pass 5 Hz → downsample to 50 Hz → ${downsampled.length} samples',
    ));

    // Emit the envelope as raw signal so the user can see the respiratory
    // waveform after processing.
    for (final double v in downsampled) {
      session.emitRawSample(v);
    }

    // ── Stage 4: Welch periodogram ────────────────────────────────────────
    final WelchResult welch = welchPeriodogram(
      downsampled,
      50,
      windowLength: math.min(2048, downsampled.length),
    );
    final int best = _bestIndex(welch.freqs, welch.psd, 0.1, 0.5);
    final double freq = best < 0 ? 0 : welch.freqs[best];
    final double rr = freq * 60;
    session.emitDiagnostic(DiagnosticEvent(
      stage: 'Welch PSD',
      message: best < 0
          ? 'No dominant frequency in 0.1–0.5 Hz band'
          : 'Dominant freq ${freq.toStringAsFixed(3)} Hz'
              ' → RR ${rr.toStringAsFixed(1)} breaths/min',
      level: best < 0 ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
    ));

    // ── Stage 5: confidence ───────────────────────────────────────────────
    final double confidence = rr > 0 ? 0.72 : 0.0;
    final MeasurementStatus status = statusFromConfidence(confidence);
    session.emitDiagnostic(DiagnosticEvent(
      stage: 'confidence',
      message: 'confidence=${confidence.toStringAsFixed(2)} → ${status.name}',
      level:
          status == MeasurementStatus.failed
              ? DiagnosticSeverity.error
              : DiagnosticSeverity.info,
    ));

    return buildMeasurement(
      id: id,
      capturedAt: started,
      duration: DateTime.now().difference(started),
      status: status,
      confidence: confidence,
      primary: rr > 0
          ? ScalarReading(
              label: 'respiratory_rate',
              value: rr,
              unit: 'breaths_per_min',
            )
          : null,
      secondary: <ScalarReading>[
        ScalarReading(label: 'dominant_freq', value: freq, unit: 'Hz'),
      ],
      extras: <String, dynamic>{
        'sample_rate_hz': 16000,
        'samples_used': samples.length,
      },
    );
  }
}

double _rmsOf(List<double> xs) {
  if (xs.isEmpty) return 0;
  final double sumSq =
      xs.map((double v) => v * v).reduce((double a, double b) => a + b);
  return math.sqrt(sumSq / xs.length);
}

int _bestIndex(
  List<double> freqs,
  List<double> values,
  double low,
  double high,
) {
  int best = -1;
  double bestValue = -1;
  for (int i = 0; i < freqs.length; i++) {
    if (freqs[i] >= low && freqs[i] <= high && values[i] > bestValue) {
      best = i;
      bestValue = values[i];
    }
  }
  return best;
}
