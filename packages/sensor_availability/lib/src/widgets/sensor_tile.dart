import 'package:flutter/material.dart';

import '../sensor_descriptor.dart';
import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';

class SensorTile extends StatelessWidget {
  const SensorTile({required this.descriptor, required this.report, super.key});

  final SensorDescriptor descriptor;
  final SensorReport report;

  @override
  Widget build(BuildContext context) {
    final Color color = _statusColor(context, report.status);
    return ExpansionTile(
      leading: Icon(_categoryIcon(descriptor.category), color: color),
      title: Text(descriptor.displayName),
      subtitle: Text(
        descriptor.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Chip(
        label: Text(report.status.label),
        backgroundColor: color.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
      expandedAlignment: Alignment.topLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Detection method: ${report.method}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (report.detail.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(report.detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Color _statusColor(BuildContext context, SensorStatus status) {
    switch (status) {
      case SensorStatus.available:
        return Colors.green.shade700;
      case SensorStatus.unavailable:
        return Colors.red.shade700;
      case SensorStatus.unknown:
        return Colors.orange.shade700;
      case SensorStatus.needsPermission:
        return Colors.blue.shade700;
    }
  }

  IconData _categoryIcon(SensorCategory category) {
    switch (category) {
      case SensorCategory.motionAndOrientation:
        return Icons.threesixty;
      case SensorCategory.environment:
        return Icons.wb_sunny_outlined;
      case SensorCategory.proximityAndDepth:
        return Icons.center_focus_strong_outlined;
      case SensorCategory.radio:
        return Icons.wifi_tethering;
      case SensorCategory.biometric:
        return Icons.fingerprint;
      case SensorCategory.vitals:
        return Icons.favorite_outline;
      case SensorCategory.system:
        return Icons.memory;
      case SensorCategory.audioVisual:
        return Icons.camera_alt_outlined;
    }
  }
}
