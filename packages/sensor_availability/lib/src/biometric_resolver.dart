import 'biometric_catalog.dart';
import 'biometric_descriptor.dart';
import 'biometric_id.dart';
import 'biometric_report.dart';
import 'sensor_id.dart';
import 'sensor_report.dart';
import 'sensor_status.dart';

/// Derives biometric availability from a list of [SensorReport]s.
List<BiometricReport> resolveBiometrics(List<SensorReport> sensorReports) {
  final Map<SensorId, SensorStatus> byId = <SensorId, SensorStatus>{
    for (final SensorReport r in sensorReports) r.id: r.status,
  };
  return <BiometricReport>[
    for (final BiometricDescriptor d in biometricCatalog) _resolveOne(d, byId),
  ];
}

BiometricReport _resolveOne(
  BiometricDescriptor d,
  Map<SensorId, SensorStatus> byId,
) {
  final List<SensorId> available = <SensorId>[];
  final List<SensorId> uncertain = <SensorId>[];
  for (final SensorId s in d.sourceSensors) {
    switch (byId[s] ?? SensorStatus.unknown) {
      case SensorStatus.available:
        available.add(s);
      case SensorStatus.unknown:
      case SensorStatus.needsPermission:
        uncertain.add(s);
      case SensorStatus.unavailable:
        break;
    }
  }
  final BiometricStatus status;
  if (available.isNotEmpty) {
    status = BiometricStatus.available;
  } else if (uncertain.isNotEmpty) {
    status = BiometricStatus.potentiallyAvailable;
  } else {
    status = BiometricStatus.unavailable;
  }
  return BiometricReport(
    id: d.id,
    status: status,
    availableSensors: available,
    uncertainSensors: uncertain,
  );
}
