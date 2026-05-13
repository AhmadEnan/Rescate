import 'sensor_id.dart';

class SensorDescriptor {
  const SensorDescriptor({
    required this.id,
    required this.displayName,
    required this.category,
    required this.description,
  });

  final SensorId id;
  final String displayName;
  final SensorCategory category;
  final String description;
}
