import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectSystemHardware(NativeProbe probe) {
  return <SensorReport>[
    _detectHallEffect(probe),
    _detectThermistor(probe),
    _detectStrainGauge(probe),
  ];
}

SensorReport _detectHallEffect(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.hallEffect,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isNotEmpty) {
    if (probe.hasAndroidSensorType(AndroidSensorType.hingeAngle) ||
        probe.sensorNameContains('hall')) {
      return const SensorReport(
        id: SensorId.hallEffect,
        status: SensorStatus.available,
        method: 'TYPE_HINGE_ANGLE / vendor name match',
      );
    }
    return const SensorReport(
      id: SensorId.hallEffect,
      status: SensorStatus.unavailable,
      method: 'TYPE_HINGE_ANGLE',
    );
  }
  return const SensorReport(
    id: SensorId.hallEffect,
    status: SensorStatus.unknown,
    method: 'iOS',
    detail: 'iOS does not expose hall-effect sensors publicly',
  );
}

SensorReport _detectThermistor(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.internalThermistor,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.thermistor == null) {
    return const SensorReport(
      id: SensorId.internalThermistor,
      status: SensorStatus.unknown,
      method: 'iOS',
      detail: 'iOS exposes no public thermal-sensor API',
    );
  }
  return SensorReport(
    id: SensorId.internalThermistor,
    status: probe.thermistor!
        ? SensorStatus.available
        : SensorStatus.unavailable,
    method: 'PowerManager.getCurrentThermalStatus',
  );
}

SensorReport _detectStrainGauge(NativeProbe probe) {
  return const SensorReport(
    id: SensorId.strainGauge,
    status: SensorStatus.unknown,
    method: 'no public API',
    detail:
        'No public sensor API for chassis strain / squeeze on Android or iOS',
  );
}
