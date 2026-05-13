import 'package:sensor_availability/sensor_availability.dart';

enum MeasurementStatus { ok, lowConfidence, failed, stub }

class ScalarReading {
  const ScalarReading({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final double value;
  final String unit;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'label': label, 'value': value, 'unit': unit};
  }

  factory ScalarReading.fromJson(Map<String, dynamic> json) {
    return ScalarReading(
      label: json['label'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String,
    );
  }
}

class BiometricMeasurement {
  const BiometricMeasurement({
    required this.id,
    required this.capturedAt,
    required this.duration,
    required this.status,
    required this.confidence,
    required this.sourceSensors,
    required this.methodology,
    required this.biomarker,
    required this.application,
    required this.displayName,
    this.primary,
    this.secondary = const <ScalarReading>[],
    this.qualityFlags = const <String>[],
    this.extras,
  });

  static const int schemaVersion = 1;

  final BiometricId id;
  final DateTime capturedAt;
  final Duration duration;
  final MeasurementStatus status;
  final double confidence;
  final ScalarReading? primary;
  final List<ScalarReading> secondary;
  final List<String> qualityFlags;
  final List<SensorId> sourceSensors;
  final String methodology;
  final String biomarker;
  final String application;
  final String displayName;
  final Map<String, dynamic>? extras;

  Map<String, dynamic> toLLMRecord() {
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'biometric_id': id.name,
      'display_name': displayName,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'duration_ms': duration.inMilliseconds,
      'status': status.name,
      'confidence': confidence.clamp(0.0, 1.0),
      'primary': primary?.toJson(),
      'secondary': secondary
          .map((ScalarReading reading) => reading.toJson())
          .toList(growable: false),
      'quality_flags': List<String>.unmodifiable(qualityFlags),
      'source_sensors': sourceSensors
          .map((SensorId sensor) => sensor.name)
          .toList(growable: false),
      'methodology': methodology,
      'biomarker': biomarker,
      'application': application,
      if (extras != null) 'extras': extras,
    };
  }

  factory BiometricMeasurement.fromLLMRecord(Map<String, dynamic> json) {
    final BiometricId id = BiometricId.values.firstWhere(
      (BiometricId value) => value.name == json['biometric_id'],
    );
    final MeasurementStatus status = MeasurementStatus.values.firstWhere(
      (MeasurementStatus value) => value.name == json['status'],
    );
    final Object? primaryJson = json['primary'];
    return BiometricMeasurement(
      id: id,
      capturedAt: DateTime.parse(json['captured_at'] as String),
      duration: Duration(milliseconds: json['duration_ms'] as int),
      status: status,
      confidence: (json['confidence'] as num).toDouble(),
      primary: primaryJson == null
          ? null
          : ScalarReading.fromJson(primaryJson as Map<String, dynamic>),
      secondary: (json['secondary'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ScalarReading.fromJson)
          .toList(growable: false),
      qualityFlags: (json['quality_flags'] as List<dynamic>)
          .cast<String>()
          .toList(growable: false),
      sourceSensors: (json['source_sensors'] as List<dynamic>)
          .cast<String>()
          .map(
            (String name) => SensorId.values.firstWhere(
              (SensorId value) => value.name == name,
            ),
          )
          .toList(growable: false),
      methodology: json['methodology'] as String,
      biomarker: json['biomarker'] as String,
      application: json['application'] as String,
      displayName: json['display_name'] as String,
      extras: json['extras'] as Map<String, dynamic>?,
    );
  }
}
