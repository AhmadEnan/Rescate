import 'package:sensor_availability/sensor_availability.dart';

import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class ProximityRespirationEstimator implements BiometricEstimator {
  const ProximityRespirationEstimator(this.id);

  @override
  final BiometricId id;

  @override
  Duration get suggestedDuration => const Duration(seconds: 60);

  @override
  String get captureInstruction => 'Hold the device near chest motion.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    final SensorId source = id == BiometricId.infraredRespiration
        ? SensorId.proximityIr
        : SensorId.proximityUltrasonic;
    return hasAnySensor(availability, <SensorId>[source]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final String flag = id == BiometricId.infraredRespiration
        ? 'raw_proximity_unavailable'
        : 'raw_proximity_unavailable';
    return buildMeasurement(
      id: id,
      capturedAt: DateTime.now(),
      duration: Duration.zero,
      status: MeasurementStatus.stub,
      confidence: 0,
      primary: null,
      qualityFlags: <String>[flag],
    );
  }
}
