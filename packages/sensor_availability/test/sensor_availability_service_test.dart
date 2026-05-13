import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';
import 'package:sensor_availability/src/platform/native_sensor_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(NativeSensorChannel.channelName);

  void handle(Object? Function(MethodCall call) responder) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          return responder(call);
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('detectAll produces a report for every catalog entry', () async {
    handle((MethodCall call) {
      switch (call.method) {
        case 'listNativeSensors':
          return <Map<String, Object>>[
            <String, Object>{
              'type': 1,
              'name': 'BMI270 Accelerometer',
              'vendor': 'Bosch',
            },
            <String, Object>{
              'type': 4,
              'name': 'BMI270 Gyroscope',
              'vendor': 'Bosch',
            },
            <String, Object>{
              'type': 2,
              'name': 'AK09918 Magnetometer',
              'vendor': 'AKM',
            },
            <String, Object>{
              'type': 5,
              'name': 'TMD2725 Light',
              'vendor': 'AMS',
            },
            <String, Object>{
              'type': 8,
              'name': 'TMD2725 Proximity',
              'vendor': 'AMS',
            },
          ];
        case 'motionAvailability':
          return <String, Object>{
            'accel': true,
            'gyro': true,
            'mag': true,
            'baro': false,
          };
        case 'cameraDepthCapability':
          return <String, Object>{
            'hasDepthOutputCamera': false,
            'hasToF': false,
            'hasLidar': false,
          };
        case 'uwbRadarAvailability':
          return <String, Object>{'uwb': false, 'radar': false};
        case 'biometryAvailability':
          return <String, Object>{
            'fingerprint': true,
            'face': false,
            'iris': false,
            'faceStrongGuarantee': false,
          };
        case 'thermalAvailability':
          return <String, Object>{'thermistor': true};
        case 'microphoneAvailability':
          return <String, Object>{'available': true};
        case 'cameraList':
          return <String>['0', '1'];
        case 'hasSystemFeature':
          return false;
      }
      return null;
    });

    final SensorAvailabilityService service =
        SensorAvailabilityService.forTesting(NativeSensorChannel());
    await service.detectAll();

    expect(service.isReady, isTrue);
    expect(service.reports.length, 26);

    // Spot-check a handful of expected statuses with the canned responses above.
    expect(service.get(SensorId.accelerometer).status, SensorStatus.available);
    expect(service.get(SensorId.barometer).status, SensorStatus.unavailable);
    expect(service.get(SensorId.ambientLight).status, SensorStatus.available);
    expect(service.get(SensorId.proximityIr).status, SensorStatus.available);
    expect(service.get(SensorId.lidar).status, SensorStatus.unavailable);
    expect(service.get(SensorId.uwb).status, SensorStatus.unavailable);
    expect(
      service.get(SensorId.fingerprintCapacitive).status,
      SensorStatus.unknown,
    );
    expect(
      service.get(SensorId.fingerprintOptical).status,
      SensorStatus.unknown,
    );
    expect(service.get(SensorId.iris).status, SensorStatus.unavailable);
    expect(service.get(SensorId.heartRatePpg).status, SensorStatus.unavailable);
    expect(service.get(SensorId.memsMicrophone).status, SensorStatus.available);
    expect(
      service.get(SensorId.cmosImageSensor).status,
      SensorStatus.available,
    );
    expect(service.get(SensorId.strainGauge).status, SensorStatus.unknown);
  });

  test(
    'detectAll without a plugin handler produces all-unknown report',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final SensorAvailabilityService service =
          SensorAvailabilityService.forTesting(NativeSensorChannel());
      await service.detectAll();

      expect(service.reports.length, 26);
      for (final SensorReport r in service.reports) {
        expect(
          <SensorStatus>{SensorStatus.unknown, SensorStatus.unavailable},
          contains(r.status),
          reason:
              '${r.id} should not be available without a plugin handler '
              '(got ${r.status})',
        );
      }
    },
  );
}
