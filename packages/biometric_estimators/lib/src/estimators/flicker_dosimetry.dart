import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/camera_ppg_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import '../dsp/fft.dart';
import 'estimator_utils.dart';

class FlickerDosimetryEstimator implements BiometricEstimator {
  FlickerDosimetryEstimator({CameraPpgSource? source})
    : _source = source ?? CameraPpgSource(frontFacing: true, flash: false);

  final CameraPpgSource _source;

  @override
  BiometricId get id => BiometricId.flickerDosimetry;

  @override
  Duration get suggestedDuration => const Duration(seconds: 5);

  @override
  String get captureInstruction =>
      'Point the front camera toward the light source.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.flicker]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    final List<double> samples = await collectWindow(
      _source.meanRedChannel(),
      suggestedDuration,
      session,
    );
    final Duration duration = DateTime.now().difference(started);
    final double fs = sampleRateFromCount(samples.length, duration, 60);
    final double highHz = math.min(120, fs * 0.45);
    final double freq = highHz <= 5
        ? 0
        : dominantFrequency(samples, fs, lowHz: 5, highHz: highHz);
    final double maxValue = samples.isEmpty ? 0 : samples.reduce(math.max);
    final double minValue = samples.isEmpty ? 0 : samples.reduce(math.min);
    final double modulation = maxValue + minValue == 0
        ? 0
        : ((maxValue - minValue) / (maxValue + minValue)).abs();
    final double confidence = freq > 0 ? 0.8 : 0.0;
    return buildMeasurement(
      id: id,
      capturedAt: started,
      duration: duration,
      status: statusFromConfidence(confidence),
      confidence: confidence,
      primary: freq > 0
          ? ScalarReading(label: 'dominant_flicker_hz', value: freq, unit: 'Hz')
          : null,
      secondary: <ScalarReading>[
        ScalarReading(
          label: 'modulation_depth',
          value: modulation,
          unit: 'unitless',
        ),
      ],
      extras: <String, dynamic>{
        'sample_rate_hz': fs,
        'frames_used': samples.length,
      },
    );
  }
}
