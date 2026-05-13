import 'package:sensor_availability/sensor_availability.dart';

import 'biometric_measurement.dart';

abstract class BiometricMeasurementRepository {
  Future<void> insert(BiometricMeasurement measurement);

  Future<BiometricMeasurement?> latestFor(BiometricId id);

  Future<List<BiometricMeasurement>> historyFor(
    BiometricId id, {
    int limit = 50,
  });
}
