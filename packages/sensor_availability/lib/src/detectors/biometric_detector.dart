import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

const String _subtypeUnknown =
    'OS reports biometric capability but does not expose the underlying sensor subtype';

List<SensorReport> detectBiometric(NativeProbe probe) {
  if (!probe.platformSupported || probe.biometry == null) {
    return _allUnknown();
  }
  final BiometryAvailability b = probe.biometry!;

  // Three fingerprint subtypes — we know fingerprint is present or not, but
  // not which technology. Report each as unknown when present, unavailable
  // when absent.
  final SensorReport fpCap = _fingerprintReport(
    SensorId.fingerprintCapacitive,
    b,
  );
  final SensorReport fpOpt = _fingerprintReport(SensorId.fingerprintOptical, b);
  final SensorReport fpUlt = _fingerprintReport(
    SensorId.fingerprintUltrasonic,
    b,
  );

  // Structured-light face: only confirmed when iOS reports Face ID or Android
  // exposes FEATURE_FACE plus a strong-class face hardware guarantee. Otherwise
  // generic face auth could be a 2D camera, not structured light → unknown.
  final SensorReport face;
  if (b.face && b.faceStrongGuarantee) {
    face = const SensorReport(
      id: SensorId.structuredLightFace,
      status: SensorStatus.available,
      method: 'LAContext.faceID / BIOMETRIC_STRONG face',
    );
  } else if (b.face) {
    face = const SensorReport(
      id: SensorId.structuredLightFace,
      status: SensorStatus.unknown,
      method: 'FEATURE_FACE',
      detail:
          'Face authentication present but not class-3 — could be 2D camera, not structured light',
    );
  } else {
    face = const SensorReport(
      id: SensorId.structuredLightFace,
      status: SensorStatus.unavailable,
      method: 'LAContext / FEATURE_FACE',
    );
  }

  final SensorReport iris;
  if (b.iris) {
    iris = const SensorReport(
      id: SensorId.iris,
      status: SensorStatus.available,
      method: 'FEATURE_IRIS',
    );
  } else {
    iris = const SensorReport(
      id: SensorId.iris,
      status: SensorStatus.unavailable,
      method: 'FEATURE_IRIS',
    );
  }

  return <SensorReport>[fpCap, fpOpt, fpUlt, face, iris];
}

SensorReport _fingerprintReport(SensorId id, BiometryAvailability b) {
  if (b.fingerprint) {
    return SensorReport(
      id: id,
      status: SensorStatus.unknown,
      method: 'FEATURE_FINGERPRINT',
      detail: _subtypeUnknown,
    );
  }
  return SensorReport(
    id: id,
    status: SensorStatus.unavailable,
    method: 'FEATURE_FINGERPRINT',
  );
}

List<SensorReport> _allUnknown() {
  const String reason = 'Native biometry query unavailable';
  return const <SensorReport>[
    SensorReport(
      id: SensorId.fingerprintCapacitive,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.fingerprintOptical,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.fingerprintUltrasonic,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.structuredLightFace,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.iris,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
  ];
}
