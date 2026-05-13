import 'package:flutter/material.dart';

import '../biometric_catalog.dart';
import '../biometric_descriptor.dart';
import '../biometric_id.dart';
import '../biometric_report.dart';
import '../sensor_availability_service.dart';
import '../sensor_id.dart';

class BiometricAvailabilityScreen extends StatefulWidget {
  const BiometricAvailabilityScreen({this.service, this.onTileTap, super.key});

  final SensorAvailabilityService? service;
  final void Function(BiometricId id)? onTileTap;

  @override
  State<BiometricAvailabilityScreen> createState() =>
      _BiometricAvailabilityScreenState();
}

class _BiometricAvailabilityScreenState
    extends State<BiometricAvailabilityScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Biometrics'),
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
            : _BiometricList(
                reports: _service.biometrics,
                onTileTap: widget.onTileTap,
              ),
      ),
    );
  }
}

class _BiometricList extends StatelessWidget {
  const _BiometricList({required this.reports, required this.onTileTap});

  final List<BiometricReport> reports;
  final void Function(BiometricId id)? onTileTap;

  @override
  Widget build(BuildContext context) {
    final Map<BiometricStatus, int> counts = <BiometricStatus, int>{
      for (final BiometricStatus s in BiometricStatus.values) s: 0,
    };
    for (final BiometricReport r in reports) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }

    final List<Widget> children = <Widget>[
      _SummaryHeader(counts: counts, total: reports.length),
    ];
    for (final BiometricReport r in reports) {
      children.add(
        _BiometricTile(
          descriptor: biometricDescriptorFor(r.id),
          report: r,
          onTileTap: onTileTap,
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.counts, required this.total});

  final Map<BiometricStatus, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final int available = counts[BiometricStatus.available] ?? 0;
    final int potential = counts[BiometricStatus.potentiallyAvailable] ?? 0;
    final int unavailable = counts[BiometricStatus.unavailable] ?? 0;

    final TextStyle? small = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$available / $total measurable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '$potential potential · $unavailable unavailable',
              style: small,
            ),
          ],
        ),
      ),
    );
  }
}

class _BiometricTile extends StatelessWidget {
  const _BiometricTile({
    required this.descriptor,
    required this.report,
    required this.onTileTap,
  });

  final BiometricDescriptor descriptor;
  final BiometricReport report;
  final void Function(BiometricId id)? onTileTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTileTap == null ? null : () => onTileTap!(descriptor.id),
      leading: _StatusIcon(status: report.status),
      trailing: onTileTap == null ? null : const Icon(Icons.chevron_right),
      title: Text(descriptor.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(descriptor.biomarker),
          const SizedBox(height: 2),
          Text(
            descriptor.application,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            _sourceLine(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  String _sourceLine() {
    String label(SensorId id) => id.name;
    switch (report.status) {
      case BiometricStatus.available:
        return 'via ${report.availableSensors.map(label).join(', ')}';
      case BiometricStatus.potentiallyAvailable:
        return 'pending ${report.uncertainSensors.map(label).join(', ')}';
      case BiometricStatus.unavailable:
        return 'requires ${descriptor.sourceSensors.map(label).join(' or ')}';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final BiometricStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case BiometricStatus.available:
        return const Icon(Icons.check_circle, color: Colors.green);
      case BiometricStatus.potentiallyAvailable:
        return const Icon(Icons.help_outline, color: Colors.orange);
      case BiometricStatus.unavailable:
        return Icon(
          Icons.cancel_outlined,
          color: Theme.of(context).disabledColor,
        );
    }
  }
}
