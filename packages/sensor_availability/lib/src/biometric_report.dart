import 'biometric_id.dart';
import 'sensor_id.dart';

class BiometricReport {
  const BiometricReport({
    required this.id,
    required this.status,
    required this.availableSensors,
    required this.uncertainSensors,
  });

  final BiometricId id;
  final BiometricStatus status;

  /// Source sensors confirmed `available`.
  final List<SensorId> availableSensors;

  /// Source sensors that came back `unknown` or `needsPermission`.
  /// Useful to explain a [BiometricStatus.potentiallyAvailable] result.
  final List<SensorId> uncertainSensors;
}
