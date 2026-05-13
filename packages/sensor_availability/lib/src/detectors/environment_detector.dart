import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

const int _typeColorTemperature =
    35; // not in Sensor.TYPE_* but used by some vendors
const int _typeColorRgb = 33; // common vendor "color" sensor type

List<SensorReport> detectEnvironment(NativeProbe probe) {
  return <SensorReport>[
    _detectAmbientLight(probe),
    _detectColorTemperature(probe),
    _detectFlicker(probe),
  ];
}

SensorReport _detectAmbientLight(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.ambientLight,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isEmpty) {
    return const SensorReport(
      id: SensorId.ambientLight,
      status: SensorStatus.unknown,
      method: 'iOS',
      detail: 'iOS does not publicly expose ambient light readings',
    );
  }
  final bool present = probe.hasAndroidSensorType(AndroidSensorType.light);
  return SensorReport(
    id: SensorId.ambientLight,
    status: present ? SensorStatus.available : SensorStatus.unavailable,
    method: 'TYPE_LIGHT',
  );
}

SensorReport _detectColorTemperature(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.colorTemperature,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isEmpty) {
    return const SensorReport(
      id: SensorId.colorTemperature,
      status: SensorStatus.unknown,
      method: 'iOS',
      detail: 'No public iOS API for spectral / color-temperature sensors',
    );
  }
  final bool typedHit =
      probe.hasAndroidSensorType(_typeColorTemperature) ||
      probe.hasAndroidSensorType(_typeColorRgb);
  final bool nameHit =
      probe.sensorNameContains('color') ||
      probe.sensorNameContains('spectral') ||
      probe.sensorNameContains('rgb');
  if (typedHit || nameHit) {
    return const SensorReport(
      id: SensorId.colorTemperature,
      status: SensorStatus.available,
      method: 'vendor sensor name match',
    );
  }
  return const SensorReport(
    id: SensorId.colorTemperature,
    status: SensorStatus.unavailable,
    method: 'TYPE_COLOR_*',
  );
}

SensorReport _detectFlicker(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.flicker,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isEmpty) {
    return const SensorReport(
      id: SensorId.flicker,
      status: SensorStatus.unknown,
      method: 'iOS',
      detail: 'No public iOS API for flicker detection',
    );
  }
  if (probe.sensorNameContains('flicker')) {
    return const SensorReport(
      id: SensorId.flicker,
      status: SensorStatus.available,
      method: 'vendor sensor name match',
    );
  }
  return const SensorReport(
    id: SensorId.flicker,
    status: SensorStatus.unknown,
    method: 'vendor-specific',
    detail:
        'No standard sensor type; not all flicker sensors expose a name string',
  );
}
