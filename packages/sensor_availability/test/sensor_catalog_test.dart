import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_availability/sensor_availability.dart';

void main() {
  group('sensorCatalog', () {
    test('contains all 26 sensor IDs exactly once', () {
      expect(sensorCatalog.length, 26);
      final Set<SensorId> ids = <SensorId>{
        for (final SensorDescriptor d in sensorCatalog) d.id,
      };
      expect(ids.length, 26);
    });

    test('every SensorId in the enum is present in the catalog', () {
      final Set<SensorId> catalogIds = <SensorId>{
        for (final SensorDescriptor d in sensorCatalog) d.id,
      };
      for (final SensorId id in SensorId.values) {
        expect(
          catalogIds,
          contains(id),
          reason: 'missing $id in sensorCatalog',
        );
      }
    });

    test('every descriptor has non-empty displayName and description', () {
      for (final SensorDescriptor d in sensorCatalog) {
        expect(
          d.displayName,
          isNotEmpty,
          reason: 'empty displayName for ${d.id}',
        );
        expect(
          d.description,
          isNotEmpty,
          reason: 'empty description for ${d.id}',
        );
      }
    });
  });
}
