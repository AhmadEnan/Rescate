import 'dart:math' as math;

import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/camera_ppg_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class PupillometryEstimator implements BiometricEstimator {
  PupillometryEstimator({CameraPpgSource? source})
    : _source = source ?? CameraPpgSource(frontFacing: true, flash: false);

  final CameraPpgSource _source;

  @override
  BiometricId get id => BiometricId.pupillometry;

  @override
  Duration get suggestedDuration => const Duration(seconds: 10);

  @override
  String get captureInstruction => 'Use the front camera in steady light.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.ambientLight]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    final List<double> frames = await collectWindow(
      _source.meanRedChannel(),
      suggestedDuration,
      session,
    );
    final double mean = frames.isEmpty
        ? 0
        : frames.reduce((double a, double b) => a + b) / frames.length;
    final double darkFraction = frames.isEmpty
        ? 0
        : frames.where((double v) => v < mean).length / frames.length;
    return buildMeasurement(
      id: id,
      capturedAt: started,
      duration: DateTime.now().difference(started),
      status: MeasurementStatus.lowConfidence,
      confidence: math.min(0.5, frames.length / 100),
      primary: ScalarReading(
        label: 'pupil_area_proxy',
        value: darkFraction,
        unit: 'a.u.',
      ),
      qualityFlags: const <String>[
        'research_grade_uncalibrated',
        'no_face_detection',
      ],
      extras: <String, dynamic>{'frames_used': frames.length},
    );
  }
}
