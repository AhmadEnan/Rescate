import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';

SensorReport _r(SensorId id, SensorStatus s) =>
    SensorReport(id: id, status: s, method: 'test');

List<SensorReport> _allWith(Map<SensorId, SensorStatus> overrides) {
  return <SensorReport>[
    for (final SensorId id in SensorId.values)
      _r(id, overrides[id] ?? SensorStatus.unavailable),
  ];
}

void main() {
  test('every biometric in the catalog resolves to a report', () {
    final List<BiometricReport> out = resolveBiometrics(_allWith({}));
    expect(out.length, biometricCatalog.length);
    expect(
      out.map((BiometricReport r) => r.id).toSet(),
      biometricCatalog.map((BiometricDescriptor d) => d.id).toSet(),
    );
  });

  test('available source sensor → BiometricStatus.available', () {
    final List<BiometricReport> out = resolveBiometrics(
      _allWith(<SensorId, SensorStatus>{
        SensorId.heartRatePpg: SensorStatus.available,
      }),
    );
    final BiometricReport ppg = out.firstWhere(
      (BiometricReport r) => r.id == BiometricId.ppgCardiovascular,
    );
    expect(ppg.status, BiometricStatus.available);
    expect(ppg.availableSensors, <SensorId>[SensorId.heartRatePpg]);
  });

  test('any-of: lidar OR structured light is enough for wound morphometry', () {
    final List<BiometricReport> out = resolveBiometrics(
      _allWith(<SensorId, SensorStatus>{
        SensorId.structuredLightFace: SensorStatus.available,
      }),
    );
    expect(
      out
          .firstWhere(
            (BiometricReport r) => r.id == BiometricId.wound3dMorphometry,
          )
          .status,
      BiometricStatus.available,
    );
  });

  test('unknown source → potentiallyAvailable', () {
    final List<BiometricReport> out = resolveBiometrics(
      _allWith(<SensorId, SensorStatus>{
        SensorId.uwb: SensorStatus.unknown,
        SensorId.radar: SensorStatus.unavailable,
      }),
    );
    final BiometricReport radar = out.firstWhere(
      (BiometricReport r) => r.id == BiometricId.radarCardiopulmonary,
    );
    expect(radar.status, BiometricStatus.potentiallyAvailable);
    expect(radar.uncertainSensors, <SensorId>[SensorId.uwb]);
  });

  test('all sources unavailable → unavailable', () {
    final List<BiometricReport> out = resolveBiometrics(_allWith({}));
    expect(
      out
          .firstWhere((BiometricReport r) => r.id == BiometricId.spirometry)
          .status,
      BiometricStatus.unavailable,
    );
  });
}
