import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sensor_availability/sensor_availability.dart';

import '../core/biometric_estimator.dart';
import '../core/biometric_measurement.dart';
import '../core/capture_protocol.dart';
import '../core/capture_session.dart';
import '../core/diagnostic_event.dart';
import '../core/measurement_repository.dart';
import '../registry.dart';

class BiometricDetailScreen extends StatefulWidget {
  const BiometricDetailScreen({
    required this.id,
    required this.measurementStore,
    this.estimator,
    this.availability,
    super.key,
  });

  final BiometricId id;
  final BiometricMeasurementRepository measurementStore;
  final BiometricEstimator? estimator;
  final SensorAvailabilityService? availability;

  @override
  State<BiometricDetailScreen> createState() => _BiometricDetailScreenState();
}
class _BiometricDetailScreenState extends State<BiometricDetailScreen> {
  late final BiometricEstimator _estimator =
      widget.estimator ?? BiometricEstimatorRegistry.instance.forId(widget.id);
  late final SensorAvailabilityService _availability =
      widget.availability ?? SensorAvailabilityService.instance;

  BiometricMeasurement? _latest;
  List<BiometricMeasurement> _history = const <BiometricMeasurement>[];

  // Active capture state
  CaptureSession? _activeSession;
  StreamSubscription<double>? _progressSub;
  double _progress = 0;
  bool _loading = true;
  bool _capturing = false;
  String? _error;

  // Last-capture diagnostics — retained after capture ends so the user can
  // inspect them alongside the result (or the failure).
  CaptureSession? _lastSession;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _activeSession?.cancel();
    unawaited(_activeSession?.close());
    unawaited(_progressSub?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final BiometricMeasurement? latest =
        await widget.measurementStore.latestFor(widget.id);
    final List<BiometricMeasurement> history =
        await widget.measurementStore.historyFor(widget.id, limit: 10);
    if (!mounted) {
      return;
    }
    setState(() {
      _latest = latest;
      _history = history;
      _loading = false;
    });
  }

  Future<void> _capture() async {
    if (!_estimator.isSupportedBy(_availability)) {
      setState(() => _error = 'Not supported on this device.');
      return;
    }
    final CaptureSession session = CaptureSession();
    setState(() {
      _activeSession = session;
      _lastSession = session;
      _capturing = true;
      _progress = 0;
      _error = null;
    });
    _progressSub = session.progress.listen((double value) {
      if (mounted) {
        setState(() => _progress = value);
      }
    });
    try {
      final BiometricMeasurement measurement =
          await _estimator.capture(session);
      if (measurement.status != MeasurementStatus.failed) {
        await widget.measurementStore.insert(measurement);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _latest = measurement;
        _error = measurement.status == MeasurementStatus.failed
            ? _failureMessage(measurement)
            : null;
      });
      await _refresh();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      await _progressSub?.cancel();
      await session.close();
      if (mounted) {
        setState(() {
          _capturing = false;
          _activeSession = null;
          _progress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final BiometricDescriptor descriptor = biometricDescriptorFor(widget.id);
    final bool supported = _estimator.isSupportedBy(_availability);
    final CaptureSession? last = _lastSession;
    return Scaffold(
      appBar: AppBar(title: Text(descriptor.displayName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _HeaderCard(descriptor: descriptor),
                const SizedBox(height: 12),
                _ProtocolCard(protocol: captureProtocolFor(widget.id)),
                const SizedBox(height: 12),
                _LastReadingCard(measurement: _latest),
                const SizedBox(height: 12),

                // Live signal chart — shown during capture and frozen after.
                if (last != null) ...<Widget>[
                  _LiveSignalChart(
                    key: ValueKey<CaptureSession>(last),
                    session: last,
                    label: _rawSignalLabel(widget.id),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_capturing)
                  _CaptureProgress(
                    progress: _progress,
                    onCancel: () => _activeSession?.cancel(),
                  )
                else if (!supported)
                  const _UnsupportedNotice()
                else
                  FilledButton.icon(
                    onPressed: _capture,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Capture'),
                  ),

                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],

                // Stage-by-stage DSP diagnostics — shown after capture.
                if (last != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _LiveDiagnosticsPanel(
                    key: ValueKey<CaptureSession>(last),
                    session: last,
                  ),
                ],

                const SizedBox(height: 16),
                Text(
                  'Recent readings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final BiometricMeasurement measurement in _history)
                  _HistoryRow(measurement: measurement),
              ],
            ),
    );
  }
}

String _rawSignalLabel(BiometricId id) {
  switch (id) {
    case BiometricId.seismocardiography:
      return 'Raw accelerometer — z-axis (m/s²)';
    case BiometricId.gyrocardiography:
      return 'Raw gyroscope — y-axis (rad/s)';
    case BiometricId.ppgCardiovascular:
      return 'Raw PPG — mean red channel';
    case BiometricId.acousticRespiration:
      return 'Respiratory envelope (post-capture)';
    default:
      return 'Raw signal';
  }
}

String _failureMessage(BiometricMeasurement measurement) {
  final String flags = measurement.qualityFlags.isEmpty
      ? 'No quality flags.'
      : measurement.qualityFlags.join(', ');
  return 'Capture failed — see pipeline stages below for details. Flags: $flags';
}

// ─── Live signal chart ────────────────────────────────────────────────────────

class _LiveSignalChart extends StatefulWidget {
  const _LiveSignalChart({
    required this.session,
    required this.label,
    super.key,
  });

  final CaptureSession session;
  final String label;

  @override
  State<_LiveSignalChart> createState() => _LiveSignalChartState();
}

class _LiveSignalChartState extends State<_LiveSignalChart> {
  final List<double> _buffer = <double>[];
  StreamSubscription<double>? _sub;
  static const int _maxBuffer = 400;

  @override
  void initState() {
    super.initState();
    // Catch up on samples already emitted before this widget was built.
    final List<double> existing = widget.session.rawSampleBuffer;
    if (existing.isNotEmpty) {
      final int start =
          existing.length > _maxBuffer ? existing.length - _maxBuffer : 0;
      _buffer.addAll(existing.sublist(start));
    }
    // Subscribe for future samples.
    _sub = widget.session.rawSignal.listen((double v) {
      if (mounted) {
        setState(() {
          _buffer.add(v);
          if (_buffer.length > _maxBuffer) {
            _buffer.removeRange(0, _buffer.length - _maxBuffer);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: _buffer.length < 2
                  ? const Center(
                      child: Text(
                        'Waiting for signal…',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ClipRect(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SignalPainter(
                            samples: List<double>.of(_buffer),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  const _SignalPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      return;
    }
    double minVal = samples.first;
    double maxVal = samples.first;
    for (final double v in samples) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final double range = maxVal - minVal;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    if (range < 1e-9) {
      // Flat signal — draw a center line.
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    final Path path = Path();
    final double xStep = size.width / (samples.length - 1);
    for (int i = 0; i < samples.length; i++) {
      final double x = i * xStep;
      // Leave 4px padding top/bottom so peaks aren't clipped.
      const double pad = 4;
      final double y =
          pad +
          (1 - (samples[i] - minVal) / range) * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignalPainter old) =>
      old.samples != samples || old.color != color;
}

// ─── Live diagnostics panel ───────────────────────────────────────────────────

class _LiveDiagnosticsPanel extends StatefulWidget {
  const _LiveDiagnosticsPanel({required this.session, super.key});

  final CaptureSession session;

  @override
  State<_LiveDiagnosticsPanel> createState() => _LiveDiagnosticsPanelState();
}

class _LiveDiagnosticsPanelState extends State<_LiveDiagnosticsPanel> {
  final List<DiagnosticEvent> _events = <DiagnosticEvent>[];
  StreamSubscription<DiagnosticEvent>? _sub;

  @override
  void initState() {
    super.initState();
    // Catch up on diagnostics already emitted before this widget was built.
    _events.addAll(widget.session.diagnosticBuffer);
    // Subscribe for future diagnostics.
    _sub = widget.session.diagnostics.listen((DiagnosticEvent e) {
      if (mounted) {
        setState(() => _events.add(e));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Pipeline stages',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final DiagnosticEvent event in _events)
              _DiagnosticRow(event: event),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.event});

  final DiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = switch (event.level) {
      DiagnosticSeverity.info => Theme.of(context).colorScheme.primary,
      DiagnosticSeverity.warning => Colors.orange.shade700,
      DiagnosticSeverity.error => Theme.of(context).colorScheme.error,
    };
    final Color msgColor = switch (event.level) {
      DiagnosticSeverity.info => Theme.of(context).colorScheme.onSurface,
      DiagnosticSeverity.warning => Colors.orange.shade700,
      DiagnosticSeverity.error => Theme.of(context).colorScheme.error,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              event.stage,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              event.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: msgColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Existing widgets (unchanged) ─────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.descriptor});

  final BiometricDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              descriptor.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(descriptor.biomarker),
            const SizedBox(height: 8),
            Text(
              descriptor.methodology,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final SensorId sensor in descriptor.sourceSensors)
                  Chip(label: Text(sensor.name)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol});

  final CaptureProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Capture setup', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(protocol.preparation),
            const SizedBox(height: 12),
            Text('Steps', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            for (int i = 0; i < protocol.steps.length; i++)
              _ProtocolLine(index: i + 1, text: protocol.steps[i]),
            const SizedBox(height: 8),
            Text('Quality tips', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final String tip in protocol.qualityTips)
              _ProtocolLine(text: tip),
          ],
        ),
      ),
    );
  }
}

class _ProtocolLine extends StatelessWidget {
  const _ProtocolLine({required this.text, this.index});

  final int? index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final int? value = index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 24, child: Text(value == null ? '–' : '$value.')),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _LastReadingCard extends StatefulWidget {
  const _LastReadingCard({required this.measurement});

  final BiometricMeasurement? measurement;

  @override
  State<_LastReadingCard> createState() => _LastReadingCardState();
}

class _LastReadingCardState extends State<_LastReadingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final BiometricMeasurement? measurement = widget.measurement;
    return Card(
      child: InkWell(
        onTap: measurement == null
            ? null
            : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: measurement == null
              ? const Text('No readings yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _primaryText(measurement),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        _StatusBadge(status: measurement.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_capturedText(measurement.capturedAt)),
                    if (_expanded) ...<Widget>[
                      const SizedBox(height: 12),
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(measurement.toLLMRecord()),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _CaptureProgress extends StatelessWidget {
  const _CaptureProgress({required this.progress, required this.onCancel});

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(value: progress),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text('${(progress * 100).round()}%')),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Not supported on this device.'),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.measurement});

  final BiometricMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(measurement.status)),
      title: Text(_primaryText(measurement)),
      subtitle: Text(_capturedText(measurement.capturedAt)),
      trailing: Text(measurement.status.name),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MeasurementStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(status.name));
  }
}

String _primaryText(BiometricMeasurement measurement) {
  final ScalarReading? primary = measurement.primary;
  if (primary == null) {
    return 'No scalar reading';
  }
  return '${primary.value.toStringAsFixed(1)} ${primary.unit}';
}

String _capturedText(DateTime capturedAt) {
  final Duration age = DateTime.now().difference(capturedAt);
  if (age.inMinutes < 1) {
    return 'just now';
  }
  if (age.inHours < 1) {
    return '${age.inMinutes} min ago';
  }
  if (age.inDays < 1) {
    return '${age.inHours} h ago';
  }
  return '${age.inDays} d ago';
}

IconData _iconFor(MeasurementStatus status) {
  switch (status) {
    case MeasurementStatus.ok:
      return Icons.check_circle;
    case MeasurementStatus.lowConfidence:
      return Icons.error_outline;
    case MeasurementStatus.failed:
      return Icons.cancel_outlined;
    case MeasurementStatus.stub:
      return Icons.block;
  }
}
