import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';

void main() {
  test('registry has one matching estimator for every biometric id', () {
    final BiometricEstimatorRegistry registry =
        BiometricEstimatorRegistry.instance;

    expect(registry.all.length, BiometricId.values.length);
    for (final BiometricId id in BiometricId.values) {
      expect(registry.forId(id).id, id);
    }
  });

  test('tier B registry estimators return valid stub measurements', () async {
    const List<BiometricId> tierB = <BiometricId>[
      BiometricId.magneticBiomarkerAssay,
      BiometricId.scleralBilirubin,
      BiometricId.ocularImaging,
      BiometricId.wound3dMorphometry,
      BiometricId.gaitAnalysis,
      BiometricId.radarCardiopulmonary,
      BiometricId.dermatoglyphics,
      BiometricId.arterialStiffness,
      BiometricId.pulseOximetry,
      BiometricId.coreBodyTemperature,
    ];
    final BiometricEstimatorRegistry registry =
        BiometricEstimatorRegistry.instance;

    for (final BiometricId id in tierB) {
      final BiometricMeasurement measurement = await registry
          .forId(id)
          .capture(CaptureSession());

      expect(measurement.id, id);
      expect(measurement.status, MeasurementStatus.stub);
      expect(measurement.primary, isNull);
      expect(measurement.toLLMRecord()['biometric_id'], id.name);
    }
  });
}
