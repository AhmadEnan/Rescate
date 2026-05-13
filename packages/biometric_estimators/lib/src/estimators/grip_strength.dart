import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/imu_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import '../dsp/filters.dart';
import 'estimator_utils.dart';

class GripStrengthEstimator implements BiometricEstimator {
  GripStrengthEstimator({ImuSource? source}) : _source = source ?? ImuSource();

  final ImuSource _source;

  @override
  BiometricId get id => BiometricId.gripStrength;

  @override
  Duration get suggestedDuration => const Duration(seconds: 5);

  @override
  String get captureInstruction => 'Squeeze the phone hard with one hand.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.accelerometer]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    final List<Vector3> samples = await collectWindow(
      _source.accelerometer(
        windowSamplePeriod: const Duration(milliseconds: 10),
      ),
      suggestedDuration,
      session,
    );
    final List<double> gRemoved = samples
        .map((Vector3 v) => v.magnitude - 9.80665)
        .toList(growable: false);
    final Duration duration = DateTime.now().difference(started);
    final double fs = sampleRateFromCount(samples.length, duration, 100);
    final double highHz = math.min(50, fs * 0.45);
    final List<double> filtered = highHz <= 5
        ? gRemoved
        : Butterworth.bandPass(4, 5, highHz, fs).processAll(gRemoved);
    final double rms = filtered.isEmpty
        ? 0
        : math.sqrt(
            filtered
                    .map((double v) => v * v)
                    .reduce((double a, double b) => a + b) /
                filtered.length,
          );
    final double peakG = samples.isEmpty
        ? 0
        : samples.map((Vector3 v) => v.magnitude / 9.80665).reduce(math.max);
    final double confidence = rms > 0 ? 0.75 : 0.0;
    final BiometricDescriptor descriptor = biometricDescriptorFor(id);
    return buildMeasurement(
      id: id,
      capturedAt: started,
      duration: duration,
      status: statusFromConfidence(confidence),
      confidence: confidence,
      primary: ScalarReading(label: 'vfe_proxy', value: rms, unit: 'a.u.'),
      secondary: <ScalarReading>[
        ScalarReading(label: 'peak_g', value: peakG, unit: 'g'),
      ],
      sourceSensors: const <SensorId>[SensorId.accelerometer],
      methodology:
          'Accelerometer-only proxy - no strain gauge present on this device. ${descriptor.methodology}',
      extras: <String, dynamic>{
        'sample_rate_hz': fs,
        'samples_used': samples.length,
      },
    );
  }
}
