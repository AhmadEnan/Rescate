import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/camera_ppg_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class PpgCardiovascularEstimator implements BiometricEstimator {
  PpgCardiovascularEstimator({CameraPpgSource? source})
    : _source = source ?? CameraPpgSource();

  final CameraPpgSource _source;

  @override
  BiometricId get id => BiometricId.ppgCardiovascular;

  @override
  Duration get suggestedDuration => const Duration(seconds: 30);

  @override
  String get captureInstruction =>
      'Cover the rear camera and flash with a fingertip.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[
      SensorId.heartRatePpg,
      SensorId.cmosImageSensor,
    ]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    int rawCount = 0;
    final List<double> frames = await collectWindow(
      _source.meanRedChannel(),
      suggestedDuration,
      session,
      onRawSample: (double frame) {
        // Emit every 3rd frame (~10 Hz) for the live waveform display.
        if (rawCount++ % 3 == 0) {
          session.emitRawSample(frame);
        }
      },
    );
    if (session.isCancelled || frames.length < 30) {
      return buildMeasurement(
        id: id,
        capturedAt: started,
        duration: DateTime.now().difference(started),
        status: MeasurementStatus.failed,
        confidence: 0,
        primary: null,
        qualityFlags: const <String>['capture_cancelled_or_too_short'],
      );
    }
    final Duration duration = DateTime.now().difference(started);
    final double fs = sampleRateFromCount(frames.length, duration, 30);
    return cardiovascularFromSignal(
      id: id,
      capturedAt: started,
      duration: duration,
      signal: frames,
      fs: fs,
      lowHz: 0.7,
      highHz: 4,
      minDistance: (0.4 * fs).round().clamp(1, math.max(1, frames.length)),
      secondaryLabel: 'rmssd',
      warmupSeconds: 2.0,
      session: session,
      extras: <String, dynamic>{
        'frames_used': frames.length,
        'estimated_sample_rate_hz': fs,
      },
    );
  }
}
