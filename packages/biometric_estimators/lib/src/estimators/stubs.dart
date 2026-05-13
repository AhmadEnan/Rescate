import 'package:sensor_availability/sensor_availability.dart';

import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class StubEstimator implements BiometricEstimator {
  const StubEstimator(this.id);

  @override
  final BiometricId id;

  @override
  String get captureInstruction => 'Not supported on this device.';

  @override
  Duration get suggestedDuration => Duration.zero;

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return false;
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    return buildMeasurement(
      id: id,
      capturedAt: DateTime.now(),
      duration: Duration.zero,
      status: MeasurementStatus.stub,
      confidence: 0,
      primary: null,
      qualityFlags: const <String>['hardware_not_supported_on_this_device'],
    );
  }
}
