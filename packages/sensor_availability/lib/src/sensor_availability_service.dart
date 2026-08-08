import 'dart:async';
import 'dart:io' show Platform;

import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';

import 'biometric_id.dart';
import 'biometric_report.dart';
import 'biometric_resolver.dart';
import 'detectors/av_detector.dart';
import 'detectors/biometric_detector.dart';
import 'detectors/environment_detector.dart';
import 'detectors/motion_detector.dart';
import 'detectors/native_probe.dart';
import 'detectors/proximity_depth_detector.dart';
import 'detectors/radio_detector.dart';
import 'detectors/system_hw_detector.dart';
import 'detectors/vitals_detector.dart';
import 'platform/native_sensor_channel.dart';
import 'sensor_catalog.dart';
import 'sensor_descriptor.dart';
import 'sensor_id.dart';
import 'sensor_report.dart';
import 'sensor_status.dart';

const Duration _kNativeProbeTimeout = Duration(seconds: 2);

/// One-shot detection of all 26 sensors. Run once in `main()` and read
/// results through the singleton `instance`. Subsequent calls to
/// `detectAll()` re-probe and replace the cached report.
class SensorAvailabilityService {
  SensorAvailabilityService._({
    NativeSensorChannel? channel,
    bool Function()? isPlatformSupported,
  }) : _channel = channel ?? NativeSensorChannel(),
       _isPlatformSupportedOverride = isPlatformSupported;

  /// Default singleton used by the app at startup.
  static final SensorAvailabilityService instance =
      SensorAvailabilityService._();

  /// Test-only constructor for injecting a mocked channel.
  @visibleForTesting
  factory SensorAvailabilityService.forTesting(
    NativeSensorChannel channel, {
    bool platformSupported = true,
  }) {
    return SensorAvailabilityService._(
      channel: channel,
      isPlatformSupported: () => platformSupported,
    );
  }

  final NativeSensorChannel _channel;
  final bool Function()? _isPlatformSupportedOverride;

  List<SensorReport> _reports = const <SensorReport>[];
  bool _ready = false;
  Duration? _lastDuration;

  bool get isReady => _ready;
  Duration? get lastDetectionDuration => _lastDuration;

  /// All 26 reports in the order defined by [sensorCatalog].
  List<SensorReport> get reports => List<SensorReport>.unmodifiable(_reports);

  SensorReport get(SensorId id) {
    if (!_ready) {
      return SensorReport(
        id: id,
        status: SensorStatus.unknown,
        method: 'not-yet-detected',
        detail: 'detectAll() has not completed',
      );
    }
    return _reports.firstWhere((SensorReport r) => r.id == id);
  }

  /// Derived biometrics, computed from the current sensor reports.
  /// Empty until [detectAll] completes.
  List<BiometricReport> get biometrics =>
      _ready ? resolveBiometrics(_reports) : const <BiometricReport>[];

  BiometricReport biometric(BiometricId id) {
    return biometrics.firstWhere((BiometricReport r) => r.id == id);
  }

  Map<SensorCategory, List<SensorReport>> get grouped {
    final Map<SensorCategory, List<SensorReport>> out =
        <SensorCategory, List<SensorReport>>{};
    for (final SensorReport r in _reports) {
      final SensorDescriptor d = descriptorFor(r.id);
      out.putIfAbsent(d.category, () => <SensorReport>[]).add(r);
    }
    return out;
  }

  /// Probes every sensor via the native channel, runs all detectors, and
  /// caches the resulting 26-entry report. Safe to call multiple times.
  Future<void> detectAll() async {
    await Profiler.trace('sensors.detectAll', (trace) async {
      final Stopwatch sw = Stopwatch()..start();
      final TraceStep? probeStep = trace?.begin('sensors.probe');
      final NativeProbe probe = await _probe();
      probeStep?.op(probe.sensors.length);
      probeStep?.end();

      final TraceStep? motionStep = trace?.begin('sensors.detect.motion');
      final List<SensorReport> motion = detectMotion(probe);
      motionStep?.op(motion.length);
      motionStep?.end();

      final TraceStep? envStep = trace?.begin('sensors.detect.environment');
      final List<SensorReport> environment = detectEnvironment(probe);
      envStep?.op(environment.length);
      envStep?.end();

      final TraceStep? proxStep = trace?.begin('sensors.detect.proximityDepth');
      final List<SensorReport> proximity = detectProximityAndDepth(probe);
      proxStep?.op(proximity.length);
      proxStep?.end();

      final TraceStep? radioStep = trace?.begin('sensors.detect.radio');
      final List<SensorReport> radio = detectRadio(probe);
      radioStep?.op(radio.length);
      radioStep?.end();

      final TraceStep? bioStep = trace?.begin('sensors.detect.biometric');
      final List<SensorReport> biometric = detectBiometric(probe);
      bioStep?.op(biometric.length);
      bioStep?.end();

      final TraceStep? vitalsStep = trace?.begin('sensors.detect.vitals');
      final List<SensorReport> vitals = detectVitals(probe);
      vitalsStep?.op(vitals.length);
      vitalsStep?.end();

      final TraceStep? sysStep = trace?.begin('sensors.detect.systemHardware');
      final List<SensorReport> system = detectSystemHardware(probe);
      sysStep?.op(system.length);
      sysStep?.end();

      final TraceStep? avStep = trace?.begin('sensors.detect.audioVisual');
      final List<SensorReport> audioVisual = detectAudioVisual(probe);
      avStep?.op(audioVisual.length);
      avStep?.end();

      final List<SensorReport> all = <SensorReport>[
        ...motion,
        ...environment,
        ...proximity,
        ...radio,
        ...biometric,
        ...vitals,
        ...system,
        ...audioVisual,
      ];
      final TraceStep? orderStep = trace?.begin('sensors.orderedByCatalog');
      _reports = _orderedByCatalog(all);
      orderStep?.op(all.length);
      orderStep?.end();

      _ready = true;
      sw.stop();
      _lastDuration = sw.elapsed;
      Profiler.count('sensors.detected', all.length);
    });
  }

  Future<NativeProbe> _probe() async {
    final bool supported = _isPlatformSupported();
    if (!supported) {
      return const NativeProbe(
        platformSupported: false,
        sensors: <NativeSensorEntry>[],
        motion: null,
        depth: null,
        uwbRadar: null,
        biometry: null,
        thermistor: null,
        microphone: null,
        cameraIds: <String>[],
        featureFingerprint: null,
        featureFace: null,
        featureIris: null,
        featureMicrophone: null,
      );
    }

    final List<Future<Object?>> futures = <Future<Object?>>[
      _probeValue<List<NativeSensorEntry>>(
        'listNativeSensors',
        _channel.listNativeSensors(),
      ),
      _probeValue<MotionAvailability>(
        'motionAvailability',
        _channel.motionAvailability(),
      ),
      _probeValue<DepthAvailability>(
        'cameraDepthCapability',
        _channel.cameraDepthCapability(),
      ),
      _probeValue<UwbRadarAvailability>(
        'uwbRadarAvailability',
        _channel.uwbRadarAvailability(),
      ),
      _probeValue<BiometryAvailability>(
        'biometryAvailability',
        _channel.biometryAvailability(),
      ),
      _probeValue<bool>('thermistorAvailable', _channel.thermistorAvailable()),
      _probeValue<bool>('microphoneAvailable', _channel.microphoneAvailable()),
      _probeValue<List<String>>('cameraList', _channel.cameraList()),
      _probeValue<bool>(
        'featureFingerprint',
        _channel.hasSystemFeature('android.hardware.fingerprint'),
      ),
      _probeValue<bool>(
        'featureFace',
        _channel.hasSystemFeature('android.hardware.biometrics.face'),
      ),
      _probeValue<bool>(
        'featureIris',
        _channel.hasSystemFeature('android.hardware.biometrics.iris'),
      ),
      _probeValue<bool>(
        'featureMicrophone',
        _channel.hasSystemFeature('android.hardware.microphone'),
      ),
    ];
    final List<Object?> results = await Future.wait(futures);

    final List<NativeSensorEntry> sensors =
        (results[0] as List<NativeSensorEntry>?) ?? <NativeSensorEntry>[];

    return NativeProbe(
      platformSupported: true,
      sensors: sensors,
      motion: results[1] as MotionAvailability?,
      depth: results[2] as DepthAvailability?,
      uwbRadar: results[3] as UwbRadarAvailability?,
      biometry: results[4] as BiometryAvailability?,
      thermistor: results[5] as bool?,
      microphone: results[6] as bool?,
      cameraIds: (results[7] as List<String>?) ?? const <String>[],
      featureFingerprint: results[8] as bool?,
      featureFace: results[9] as bool?,
      featureIris: results[10] as bool?,
      featureMicrophone: results[11] as bool?,
    );
  }

  Future<T?> _probeValue<T>(String label, Future<T?> future) async {
    return Profiler.span('sensors.probe.$label', () async {
      Profiler.count('sensors.probe.calls', 1);
      try {
        return await future.timeout(
          _kNativeProbeTimeout,
          onTimeout: () {
            debugPrint('Native sensor probe timed out: $label');
            return null;
          },
        );
      } on Object catch (e) {
        debugPrint('Native sensor probe failed: $label $e');
        return null;
      }
    });
  }

  bool _isPlatformSupported() {
    final bool Function()? override = _isPlatformSupportedOverride;
    if (override != null) {
      return override();
    }
    if (kIsWeb) {
      return false;
    }
    try {
      return Platform.isAndroid || Platform.isIOS;
    } on Object {
      return false;
    }
  }

  List<SensorReport> _orderedByCatalog(List<SensorReport> reports) {
    final Map<SensorId, SensorReport> byId = <SensorId, SensorReport>{
      for (final SensorReport r in reports) r.id: r,
    };
    return <SensorReport>[
      for (final SensorDescriptor d in sensorCatalog)
        byId[d.id] ??
            SensorReport(
              id: d.id,
              status: SensorStatus.unknown,
              method: 'missing',
              detail: 'No detector produced a report for this sensor',
            ),
    ];
  }
}
