import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectVitals(NativeProbe probe) {
  return <SensorReport>[
    _detectHeartRate(probe),
    _detectSpO2(probe),
    _detectThermopile(probe),
  ];
}

SensorReport _detectHeartRate(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.heartRatePpg,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isNotEmpty) {
    final bool present =
        probe.hasAndroidSensorType(AndroidSensorType.heartRate) ||
        probe.hasAndroidSensorType(AndroidSensorType.heartBeat);
    return SensorReport(
      id: SensorId.heartRatePpg,
      status: present ? SensorStatus.available : SensorStatus.unavailable,
      method: 'TYPE_HEART_RATE / TYPE_HEART_BEAT',
    );
  }
  return const SensorReport(
    id: SensorId.heartRatePpg,
    status: SensorStatus.unavailable,
    method: 'iOS',
    detail: 'iPhone has no PPG; HealthKit only surfaces Apple Watch data',
  );
}

SensorReport _detectSpO2(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.pulseOximeter,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isNotEmpty) {
    final bool match =
        probe.sensorNameContains('oxygen') ||
        probe.sensorNameContains('spo2') ||
        probe.sensorNameContains('hrm');
    return SensorReport(
      id: SensorId.pulseOximeter,
      status: match ? SensorStatus.available : SensorStatus.unknown,
      method: 'vendor sensor name match',
      detail: match
          ? ''
          : 'No standard sensor type for SpO2; depends on vendor exposing a name string',
    );
  }
  return const SensorReport(
    id: SensorId.pulseOximeter,
    status: SensorStatus.unavailable,
    method: 'iOS',
    detail: 'iPhone has no SpO2 hardware',
  );
}

SensorReport _detectThermopile(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.skinTemperatureThermopile,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isNotEmpty) {
    final bool nameHit =
        probe.sensorNameContains('thermopile') ||
        probe.sensorNameContains('skin temperature') ||
        probe.sensorNameContains('object temperature');
    if (nameHit) {
      return const SensorReport(
        id: SensorId.skinTemperatureThermopile,
        status: SensorStatus.available,
        method: 'vendor sensor name match',
      );
    }
    final bool ambient = probe.hasAndroidSensorType(
      AndroidSensorType.ambientTemperature,
    );
    return SensorReport(
      id: SensorId.skinTemperatureThermopile,
      status: SensorStatus.unknown,
      method: 'TYPE_AMBIENT_TEMPERATURE',
      detail: ambient
          ? 'Ambient-temperature sensor present but cannot confirm contact-free thermopile'
          : 'No standard Android type for skin/object thermopile',
    );
  }
  return const SensorReport(
    id: SensorId.skinTemperatureThermopile,
    status: SensorStatus.unavailable,
    method: 'iOS',
    detail: 'iPhone has no thermopile sensor',
  );
}
