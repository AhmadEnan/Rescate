import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/imu_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class SeismocardiographyEstimator implements BiometricEstimator {
  SeismocardiographyEstimator({ImuSource? source})
    : _source = source ?? ImuSource();

  final ImuSource _source;

  @override
  BiometricId get id => BiometricId.seismocardiography;

  @override
  Duration get suggestedDuration => const Duration(seconds: 60);

  @override
  String get captureInstruction =>
      'Place the phone flat on the chest and remain still.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.accelerometer]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    int rawCount = 0;
    final List<Vector3> samples = await collectWindow(
      _source.accelerometer(
        windowSamplePeriod: const Duration(milliseconds: 10),
      ),
      suggestedDuration,
      session,
      onRawSample: (Vector3 v) {
        // Emit z-axis at ~20 Hz for the live waveform display.
        if (rawCount++ % 5 == 0) {
          session.emitRawSample(v.z);
        }
      },
    );
    if (session.isCancelled || samples.length < 50) {
      return buildMeasurement(
        id: id,
        capturedAt: started,
        duration: DateTime.now().difference(started),
        status: MeasurementStatus.failed,
        confidence: 0,
        primary: null,
      );
    }
    final List<double> z = samples
        .map((Vector3 v) => v.z)
        .toList(growable: false);
    final List<double> magnitudes = samples
        .map((Vector3 v) => v.magnitude)
        .toList(growable: false);
    final List<String> flags = <String>[];
    if (stdDev(magnitudes) > 1.5) {
      flags.add('phone_orientation_unstable');
    }
    final Duration duration = DateTime.now().difference(started);
    final double fs = sampleRateFromCount(samples.length, duration, 100);
    return cardiovascularFromSignal(
      id: id,
      capturedAt: started,
      duration: duration,
      signal: z,
      fs: fs,
      lowHz: 0.5,
      highHz: 40,
      minDistance: (0.4 * fs).round().clamp(1, math.max(1, samples.length)),
      secondaryLabel: 'ibi_std',
      qualityFlags: flags,
      warmupSeconds: 3.0,
      session: session,
    );
  }
}
