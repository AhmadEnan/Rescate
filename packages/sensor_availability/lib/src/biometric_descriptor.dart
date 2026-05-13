import 'biometric_id.dart';
import 'sensor_id.dart';

/// Static metadata about a biometric / clinical biomarker that can be
/// derived from one or more hardware sensors.
class BiometricDescriptor {
  const BiometricDescriptor({
    required this.id,
    required this.displayName,
    required this.biomarker,
    required this.methodology,
    required this.application,
    required this.sourceSensors,
  });

  final BiometricId id;

  /// Short label, e.g. "Seismocardiography".
  final String displayName;

  /// What is actually measured, e.g. "Inter-beat intervals (IBIs), heart rate".
  final String biomarker;

  /// Algorithmic processing pipeline summary.
  final String methodology;

  /// Diagnostic application / clinical use case.
  final String application;

  /// Sensors from which this biometric can be computed. Semantics are
  /// "any-of": the biometric is measurable if at least one source sensor is
  /// physically present.
  final List<SensorId> sourceSensors;
}
