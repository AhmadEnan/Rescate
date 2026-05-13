import 'package:flutter/material.dart';

import '../sensor_availability_service.dart';
import '../sensor_catalog.dart';
import '../sensor_descriptor.dart';
import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'sensor_tile.dart';

class SensorAvailabilityScreen extends StatefulWidget {
  const SensorAvailabilityScreen({this.service, super.key});

  /// Defaults to the singleton; override in tests.
  final SensorAvailabilityService? service;

  @override
  State<SensorAvailabilityScreen> createState() =>
      _SensorAvailabilityScreenState();
}

class _SensorAvailabilityScreenState extends State<SensorAvailabilityScreen> {
  late final SensorAvailabilityService _service =
      widget.service ?? SensorAvailabilityService.instance;

  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    if (!_service.isReady) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    await _service.detectAll();
    if (!mounted) {
      return;
    }
    setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<SensorReport> reports = _service.reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Sensors'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
            tooltip: 'Re-run detection',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: !_service.isReady
            ? const Center(child: CircularProgressIndicator())
            : _ReportList(
                reports: reports,
                duration: _service.lastDetectionDuration,
              ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.reports, required this.duration});

  final List<SensorReport> reports;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final Map<SensorStatus, int> counts = <SensorStatus, int>{
      for (final SensorStatus s in SensorStatus.values) s: 0,
    };
    for (final SensorReport r in reports) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }

    final Map<SensorCategory, List<SensorReport>> grouped =
        <SensorCategory, List<SensorReport>>{};
    for (final SensorReport r in reports) {
      final SensorDescriptor d = descriptorFor(r.id);
      grouped.putIfAbsent(d.category, () => <SensorReport>[]).add(r);
    }

    final List<Widget> children = <Widget>[
      _SummaryHeader(counts: counts, total: reports.length, duration: duration),
    ];
    for (final SensorCategory cat in SensorCategory.values) {
      final List<SensorReport>? rows = grouped[cat];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      children.add(_CategoryHeader(label: cat.displayName));
      for (final SensorReport r in rows) {
        children.add(SensorTile(descriptor: descriptorFor(r.id), report: r));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.counts,
    required this.total,
    required this.duration,
  });

  final Map<SensorStatus, int> counts;
  final int total;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final int available = counts[SensorStatus.available] ?? 0;
    final int unknown = counts[SensorStatus.unknown] ?? 0;
    final int unavailable = counts[SensorStatus.unavailable] ?? 0;
    final int needsPermission = counts[SensorStatus.needsPermission] ?? 0;

    final TextStyle? small = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$available / $total detected',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '$unknown unknown · $unavailable unavailable · $needsPermission needs permission',
              style: small,
            ),
            if (duration != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('Probe took ${duration!.inMilliseconds} ms', style: small),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
