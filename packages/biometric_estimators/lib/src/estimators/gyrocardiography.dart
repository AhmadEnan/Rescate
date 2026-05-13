import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/imu_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class GyrocardiographyEstimator implements BiometricEstimator {
  GyrocardiographyEstimator({ImuSource? source})
    : _source = source ?? ImuSource();

  final ImuSource _source;

  @override
  BiometricId get id => BiometricId.gyrocardiography;

  @override
  Duration get suggestedDuration => const Duration(seconds: 60);

  @override
  String get captureInstruction =>
      'Place the phone on the chest and remain still.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.gyroscope]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    int rawCount = 0;
    final List<Vector3> samples = await collectWindow(
      _source.gyroscope(windowSamplePeriod: const Duration(milliseconds: 10)),
      suggestedDuration,
      session,
      onRawSample: (Vector3 v) {
        // Emit y-axis at ~20 Hz for the live waveform display.
        if (rawCount++ % 5 == 0) {
          session.emitRawSample(v.y);
        }
      },
    );
    final List<double> y = samples
        .map((Vector3 v) => v.y)
        .toList(growable: false);
    final Duration duration = DateTime.now().difference(started);
    final double fs = sampleRateFromCount(samples.length, duration, 100);
    return cardiovascularFromSignal(
      id: id,
      capturedAt: started,
      duration: duration,
      signal: y,
      fs: fs,
      lowHz: 0.5,
      highHz: 25,
      minDistance: (0.4 * fs).round().clamp(1, math.max(1, samples.length)),
      secondaryLabel: 'ibi_std',
      warmupSeconds: 3.0,
      session: session,
    );
  }
}
