import 'package:sensor_availability/sensor_availability.dart';

import '../acquisition/imu_source.dart';
import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_session.dart';
import 'estimator_utils.dart';

class SpirometryEstimator implements BiometricEstimator {
  SpirometryEstimator({ImuSource? source}) : _source = source ?? ImuSource();

  final ImuSource _source;

  @override
  BiometricId get id => BiometricId.spirometry;

  @override
  Duration get suggestedDuration => const Duration(seconds: 6);

  @override
  String get captureInstruction =>
      'Exhale forcefully toward the phone barometer area.';

  @override
  bool isSupportedBy(SensorAvailabilityService availability) {
    return hasAnySensor(availability, const <SensorId>[SensorId.barometer]);
  }

  @override
  Future<BiometricMeasurement> capture(CaptureSession session) async {
    final DateTime started = DateTime.now();
    final List<double> hpa = await collectWindow(
      _source.barometerHpa(),
      suggestedDuration,
      session,
    );
    double peak = 0;
    for (int i = 1; i < hpa.length; i++) {
      final double dpdt = -((hpa[i] - hpa[i - 1]) * 100.0);
      if (dpdt > peak) {
        peak = dpdt;
      }
    }
    return buildMeasurement(
      id: id,
      capturedAt: started,
      duration: DateTime.now().difference(started),
      status: MeasurementStatus.lowConfidence,
      confidence: peak > 0 ? 0.45 : 0.2,
      primary: ScalarReading(label: 'pef_proxy', value: peak, unit: 'Pa*s^-1'),
      qualityFlags: const <String>['research_grade_uncalibrated'],
      extras: <String, dynamic>{'samples_used': hpa.length},
    );
  }
}
