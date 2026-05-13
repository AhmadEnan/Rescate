import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectAudioVisual(NativeProbe probe) {
  return <SensorReport>[_detectMicrophone(probe), _detectCamera(probe)];
}

SensorReport _detectMicrophone(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.memsMicrophone,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.microphone != null) {
    return SensorReport(
      id: SensorId.memsMicrophone,
      status: probe.microphone!
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'AVAudioSession / FEATURE_MICROPHONE',
    );
  }
  if (probe.featureMicrophone != null) {
    return SensorReport(
      id: SensorId.memsMicrophone,
      status: probe.featureMicrophone!
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'FEATURE_MICROPHONE',
    );
  }
  return const SensorReport(
    id: SensorId.memsMicrophone,
    status: SensorStatus.unknown,
    method: 'fallback',
    detail: 'Native microphone query unavailable',
  );
}

SensorReport _detectCamera(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.cmosImageSensor,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.cameraIds.isEmpty) {
    return const SensorReport(
      id: SensorId.cmosImageSensor,
      status: SensorStatus.unavailable,
      method: 'CameraManager.getCameraIdList / AVCaptureDevice',
    );
  }
  return SensorReport(
    id: SensorId.cmosImageSensor,
    status: SensorStatus.available,
    method: 'CameraManager.getCameraIdList / AVCaptureDevice',
    detail: '${probe.cameraIds.length} camera(s) detected',
  );
}
