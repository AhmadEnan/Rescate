import 'dart:convert';

import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';

void main() {
  test('toLLMRecord emits canonical JSON with extras', () {
    final BiometricMeasurement measurement = BiometricMeasurement(
      id: BiometricId.ppgCardiovascular,
      capturedAt: DateTime.utc(2026, 5, 9, 14, 32, 11),
      duration: const Duration(seconds: 30),
      status: MeasurementStatus.ok,
      confidence: 0.84,
      primary: const ScalarReading(
        label: 'heart_rate',
        value: 72.4,
        unit: 'bpm',
      ),
      secondary: const <ScalarReading>[
        ScalarReading(label: 'rmssd', value: 28.1, unit: 'ms'),
        ScalarReading(label: 'ibi_count', value: 36, unit: 'count'),
      ],
      qualityFlags: const <String>['motion_artifact_low'],
      sourceSensors: const <SensorId>[SensorId.heartRatePpg],
      methodology:
          'RGB-to-HSV conversion, adaptive thresholding, peak detection',
      biomarker: 'Blood volume waveform; Heart Rate Variability (HRV)',
      application: 'Cardiovascular monitoring; blood pressure estimation',
      displayName: 'PPG Cardiovascular',
      extras: const <String, dynamic>{'sample_rate_hz': 30, 'frames_used': 870},
    );

    expect(
      jsonEncode(measurement.toLLMRecord()),
      '{"schema_version":1,"biometric_id":"ppgCardiovascular","display_name":"PPG Cardiovascular","captured_at":"2026-05-09T14:32:11.000Z","duration_ms":30000,"status":"ok","confidence":0.84,"primary":{"label":"heart_rate","value":72.4,"unit":"bpm"},"secondary":[{"label":"rmssd","value":28.1,"unit":"ms"},{"label":"ibi_count","value":36.0,"unit":"count"}],"quality_flags":["motion_artifact_low"],"source_sensors":["heartRatePpg"],"methodology":"RGB-to-HSV conversion, adaptive thresholding, peak detection","biomarker":"Blood volume waveform; Heart Rate Variability (HRV)","application":"Cardiovascular monitoring; blood pressure estimation","extras":{"sample_rate_hz":30,"frames_used":870}}',
    );
  });

  test('toLLMRecord omits extras when absent', () {
    final BiometricDescriptor descriptor = biometricDescriptorFor(
      BiometricId.pulseOximetry,
    );
    final BiometricMeasurement measurement = BiometricMeasurement(
      id: descriptor.id,
      capturedAt: DateTime.utc(2026),
      duration: Duration.zero,
      status: MeasurementStatus.stub,
      confidence: 0,
      sourceSensors: descriptor.sourceSensors,
      methodology: descriptor.methodology,
      biomarker: descriptor.biomarker,
      application: descriptor.application,
      displayName: descriptor.displayName,
    );

    expect(measurement.toLLMRecord().containsKey('extras'), isFalse);
  });
}
