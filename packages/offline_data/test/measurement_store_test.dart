import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_data/offline_data.dart';
import 'package:sensor_availability/sensor_availability.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('insert and latestFor round-trip the LLM payload', () async {
    final MeasurementStore store = await MeasurementStore.open(
      path: inMemoryDatabasePath,
    );
    final BiometricMeasurement measurement = _measurement(
      BiometricId.ppgCardiovascular,
      DateTime.utc(2026, 5, 9, 12),
    );

    await store.insert(measurement);
    final BiometricMeasurement? latest = await store.latestFor(measurement.id);

    expect(latest?.toLLMRecord(), measurement.toLLMRecord());
    await store.close();
  });

  test('historyFor returns most recent rows in descending order', () async {
    final MeasurementStore store = await MeasurementStore.open(
      path: inMemoryDatabasePath,
    );
    for (int i = 0; i < 50; i++) {
      await store.insert(
        _measurement(BiometricId.gripStrength, DateTime.utc(2026, 5, 9, 12, i)),
      );
    }

    final List<BiometricMeasurement> history = await store.historyFor(
      BiometricId.gripStrength,
      limit: 10,
    );

    expect(history.length, 10);
    expect(history.first.capturedAt.minute, 49);
    expect(history.last.capturedAt.minute, 40);
    await store.close();
  });

  test('exportLLMBundle returns canonical schema maps', () async {
    final MeasurementStore store = await MeasurementStore.open(
      path: inMemoryDatabasePath,
    );
    await store.insert(
      _measurement(BiometricId.ppgCardiovascular, DateTime.utc(2026)),
    );
    await store.insert(
      _measurement(BiometricId.gripStrength, DateTime.utc(2026, 1, 2)),
    );
    await store.insert(
      _measurement(
        BiometricId.spirometry,
        DateTime.utc(2026, 1, 3),
        status: MeasurementStatus.lowConfidence,
        qualityFlags: const <String>['research_grade_uncalibrated'],
      ),
    );
    await store.insert(
      _measurement(
        BiometricId.pupillometry,
        DateTime.utc(2026, 1, 4),
        status: MeasurementStatus.lowConfidence,
        qualityFlags: const <String>[
          'research_grade_uncalibrated',
          'no_face_detection',
        ],
      ),
    );
    await store.insert(
      _measurement(
        BiometricId.pulseOximetry,
        DateTime.utc(2026, 1, 5),
        status: MeasurementStatus.stub,
        confidence: 0,
        primary: null,
        secondary: const <ScalarReading>[],
        qualityFlags: const <String>['hardware_not_supported_on_this_device'],
      ),
    );

    final List<Map<String, dynamic>> bundle = await store.exportLLMBundle();

    expect(bundle.length, 5);
    expect(
      bundle.map((Map<String, dynamic> row) => row['biometric_id']),
      containsAll(<String>[
        BiometricId.ppgCardiovascular.name,
        BiometricId.gripStrength.name,
        BiometricId.spirometry.name,
        BiometricId.pupillometry.name,
        BiometricId.pulseOximetry.name,
      ]),
    );
    for (final Map<String, dynamic> row in bundle) {
      _expectCanonicalSchema(row);
    }
    await store.close();
  });
}

BiometricMeasurement _measurement(
  BiometricId id,
  DateTime capturedAt, {
  MeasurementStatus status = MeasurementStatus.ok,
  double confidence = 0.8,
  ScalarReading? primary = const ScalarReading(
    label: 'value',
    value: 1.0,
    unit: 'a.u.',
  ),
  List<ScalarReading> secondary = const <ScalarReading>[
    ScalarReading(label: 'count', value: 2, unit: 'count'),
  ],
  List<String> qualityFlags = const <String>['test'],
}) {
  final BiometricDescriptor descriptor = biometricDescriptorFor(id);
  return BiometricMeasurement(
    id: id,
    capturedAt: capturedAt,
    duration: const Duration(seconds: 5),
    status: status,
    confidence: confidence,
    primary: primary,
    secondary: secondary,
    qualityFlags: qualityFlags,
    sourceSensors: descriptor.sourceSensors,
    methodology: descriptor.methodology,
    biomarker: descriptor.biomarker,
    application: descriptor.application,
    displayName: descriptor.displayName,
  );
}

void _expectCanonicalSchema(Map<String, dynamic> row) {
  expect(row.keys.toSet(), <String>{
    'schema_version',
    'biometric_id',
    'display_name',
    'captured_at',
    'duration_ms',
    'status',
    'confidence',
    'primary',
    'secondary',
    'quality_flags',
    'source_sensors',
    'methodology',
    'biomarker',
    'application',
  });
  expect(row['schema_version'], BiometricMeasurement.schemaVersion);
  expect(row['biometric_id'], isA<String>());
  expect(row['display_name'], isA<String>());
  expect(row['captured_at'], isA<String>());
  expect(row['duration_ms'], isA<int>());
  expect(
    row['status'],
    isIn(MeasurementStatus.values.map((MeasurementStatus s) => s.name)),
  );
  expect(row['confidence'], isA<num>());
  expect(row['secondary'], isA<List<dynamic>>());
  expect(row['quality_flags'], isA<List<dynamic>>());
  expect(row['source_sensors'], isA<List<dynamic>>());
  expect(row['methodology'], isA<String>());
  expect(row['biomarker'], isA<String>());
  expect(row['application'], isA<String>());
}
