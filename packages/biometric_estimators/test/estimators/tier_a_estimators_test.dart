import 'dart:async';
import 'dart:math' as math;

import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:biometric_estimators/src/acquisition/camera_ppg_source.dart';
import 'package:biometric_estimators/src/acquisition/imu_source.dart';
import 'package:biometric_estimators/src/acquisition/mic_source.dart';
import 'package:biometric_estimators/src/estimators/acoustic_respiration.dart';
import 'package:biometric_estimators/src/estimators/flicker_dosimetry.dart';
import 'package:biometric_estimators/src/estimators/grip_strength.dart';
import 'package:biometric_estimators/src/estimators/gyrocardiography.dart';
import 'package:biometric_estimators/src/estimators/ppg_cardiovascular.dart';
import 'package:biometric_estimators/src/estimators/proximity_respiration.dart';
import 'package:biometric_estimators/src/estimators/pupillometry.dart';
import 'package:biometric_estimators/src/estimators/seismocardiography.dart';
import 'package:biometric_estimators/src/estimators/spirometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';

void main() {
  test('PPG estimates heart rate from synthetic red channel', () async {
    final List<double> samples = _sine(
      freq: 1.2,
      fs: 30,
      seconds: 30,
      offset: 100,
    );
    final PpgCardiovascularEstimator estimator = PpgCardiovascularEstimator(
      source: CameraPpgSource.forTesting(Stream<double>.fromIterable(samples)),
    );

    final BiometricMeasurement m = await estimator.capture(CaptureSession());
    expect(m.primary?.value, closeTo(72, 2));
    expect(m.status, MeasurementStatus.ok);
  });

  test(
    'SCG estimates heart rate from synthetic accelerometer bursts',
    () async {
      final Stream<Vector3> stream = Stream<Vector3>.fromIterable(<Vector3>[
        for (int i = 0; i < 6000; i++)
          Vector3(0, 0, 9.8 + math.sin(2 * math.pi * i / 100)),
      ]);
      final SeismocardiographyEstimator estimator = SeismocardiographyEstimator(
        source: ImuSource.forTesting(accelerometer: stream),
      );

      final BiometricMeasurement m = await estimator.capture(CaptureSession());
      expect(m.primary?.value, closeTo(60, 5));
    },
  );

  test('GCG estimates heart rate from synthetic gyroscope signal', () async {
    final Stream<Vector3> stream = Stream<Vector3>.fromIterable(<Vector3>[
      for (int i = 0; i < 6000; i++)
        Vector3(0, math.sin(2 * math.pi * i / 100), 0),
    ]);
    final GyrocardiographyEstimator estimator = GyrocardiographyEstimator(
      source: ImuSource.forTesting(gyroscope: stream),
    );

    final BiometricMeasurement m = await estimator.capture(CaptureSession());
    expect(m.primary?.value, closeTo(60, 5));
    expect(m.status, MeasurementStatus.ok);
  });

  test(
    'acoustic respiration estimates breathing rate from amplitude envelope',
    () async {
      const double fs = 16000;
      final List<double> samples = <double>[
        for (int i = 0; i < 16000 * 20; i++)
          (0.6 + (0.4 * math.sin(2 * math.pi * 0.25 * i / fs))) *
              math.sin(2 * math.pi * 500 * i / fs),
      ];
      final AcousticRespirationEstimator estimator =
          AcousticRespirationEstimator(
            source: MicSource.forTesting(Future<List<double>>.value(samples)),
          );

      final BiometricMeasurement m = await estimator.capture(CaptureSession());
      expect(m.primary?.value, closeTo(15, 1.5));
    },
  );

  test(
    'flicker dosimetry estimates flicker frequency and modulation',
    () async {
      final List<double> samples = _sine(
        freq: 20,
        fs: 60,
        seconds: 5,
        offset: 2,
        amplitude: 1,
      );
      final FlickerDosimetryEstimator estimator = FlickerDosimetryEstimator(
        source: CameraPpgSource.forTesting(
          Stream<double>.fromIterable(samples),
        ),
      );

      final BiometricMeasurement m = await estimator.capture(CaptureSession());
      expect(m.primary?.value, closeTo(20, 1));
      expect(m.secondary.first.value, closeTo(0.5, 0.1));
    },
  );

  test('grip strength emits vibration proxy and peak g', () async {
    final Stream<Vector3> stream = Stream<Vector3>.fromIterable(<Vector3>[
      for (int i = 0; i < 500; i++)
        Vector3(0.4 * math.sin(2 * math.pi * 12 * i / 100), 0, 9.8),
    ]);
    final GripStrengthEstimator estimator = GripStrengthEstimator(
      source: ImuSource.forTesting(accelerometer: stream),
    );

    final BiometricMeasurement m = await estimator.capture(CaptureSession());
    expect(m.primary!.value, greaterThan(0));
    expect(m.secondary.first.value, greaterThan(0));
  });

  test('spirometry emits low-confidence research proxy', () async {
    final Stream<double> stream = Stream<double>.fromIterable(<double>[
      for (int i = 0; i < 60; i++) 1013.0 - (i < 20 ? i * 0.02 : 0.4),
    ]);
    final SpirometryEstimator estimator = SpirometryEstimator(
      source: ImuSource.forTesting(barometer: stream),
    );

    final BiometricMeasurement m = await estimator.capture(CaptureSession());
    expect(m.status, MeasurementStatus.lowConfidence);
    expect(m.qualityFlags, contains('research_grade_uncalibrated'));
  });

  test('pupillometry emits low-confidence pupil area proxy', () async {
    final List<double> samples = <double>[
      for (int i = 0; i < 120; i++) i.isEven ? 0.2 : 0.8,
    ];
    final PupillometryEstimator estimator = PupillometryEstimator(
      source: CameraPpgSource.forTesting(Stream<double>.fromIterable(samples)),
    );

    final BiometricMeasurement m = await estimator.capture(CaptureSession());
    expect(m.primary?.label, 'pupil_area_proxy');
    expect(m.primary?.value, closeTo(0.5, 0.01));
    expect(m.status, MeasurementStatus.lowConfidence);
    expect(m.qualityFlags, contains('research_grade_uncalibrated'));
  });

  test(
    'proximity respiration variants return raw-signal unavailable stubs',
    () async {
      for (final BiometricId id in <BiometricId>[
        BiometricId.infraredRespiration,
        BiometricId.ultrasonicRespiration,
      ]) {
        final ProximityRespirationEstimator estimator =
            ProximityRespirationEstimator(id);
        final BiometricMeasurement m = await estimator.capture(
          CaptureSession(),
        );

        expect(m.id, id);
        expect(m.status, MeasurementStatus.stub);
        expect(m.primary, isNull);
        expect(m.qualityFlags, contains('raw_proximity_unavailable'));
      }
    },
  );
}

List<double> _sine({
  required double freq,
  required double fs,
  required int seconds,
  double offset = 0,
  double amplitude = 1,
}) {
  return <double>[
    for (int i = 0; i < (fs * seconds).round(); i++)
      offset + (amplitude * math.sin(2 * math.pi * freq * i / fs)),
  ];
}
