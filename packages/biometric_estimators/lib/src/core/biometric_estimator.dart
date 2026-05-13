import 'package:sensor_availability/sensor_availability.dart';

import 'biometric_measurement.dart';
import 'capture_session.dart';

abstract class BiometricEstimator {
  BiometricId get id;
  Duration get suggestedDuration;
  String get captureInstruction;

  bool isSupportedBy(SensorAvailabilityService availability);

  Future<BiometricMeasurement> capture(CaptureSession session);
}
