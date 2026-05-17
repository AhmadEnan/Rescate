import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  static const Color _bg = Color(0xFFF5EFE6);
  static const Color _red = Color(0xFFA11F2B);
  static const Color _textDark = Color(0xFF202020);
  static const Color _cardBg = Color(0xFFD9D0C7);

  @override
  Widget build(BuildContext context) {
    final BiometricDescriptor descriptor = biometricDescriptorFor(widget.id);
    final bool supported = _estimator.isSupportedBy(_availability);
    final CaptureSession? last = _lastSession;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Custom app bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: _textDark),
                  ),
                  Expanded(
                    child: Text(
                      descriptor.displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: _red,
                        strokeWidth: 3,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: <Widget>[
                        _HeaderCard(descriptor: descriptor),
                        const SizedBox(height: 12),
                        _ProtocolCard(protocol: captureProtocolFor(widget.id)),
                        const SizedBox(height: 12),
                        _LastReadingCard(measurement: _latest),
                        const SizedBox(height: 12),

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
                          _CaptureButton(onTap: _capture),

                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                color: Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],

                        if (last != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _LiveDiagnosticsPanel(
                            key: ValueKey<CaptureSession>(last),
                            session: last,
                          ),
                        ],

                        const SizedBox(height: 20),
                        Text(
                          'Recent readings',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final BiometricMeasurement measurement in _history)
                          _HistoryRow(measurement: measurement),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFA11F2B),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFA11F2B).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              'Start Capture',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            descriptor.displayName,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202020),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            descriptor.biomarker,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF202020).withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            descriptor.methodology,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF202020).withOpacity(0.45),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final SensorId sensor in descriptor.sourceSensors)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA11F2B).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    sensor.name,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFA11F2B),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol});

  final CaptureProtocol protocol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Capture setup', style: GoogleFonts.poppins(
            fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF202020),
          )),
          const SizedBox(height: 8),
          Text(protocol.preparation, style: GoogleFonts.inter(
            fontSize: 13, color: const Color(0xFF202020).withOpacity(0.6), height: 1.4,
          )),
          const SizedBox(height: 12),
          Text('Steps', style: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFA11F2B),
          )),
          const SizedBox(height: 4),
          for (int i = 0; i < protocol.steps.length; i++)
            _ProtocolLine(index: i + 1, text: protocol.steps[i]),
          const SizedBox(height: 8),
          Text('Quality tips', style: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFA11F2B),
          )),
          const SizedBox(height: 4),
          for (final String tip in protocol.qualityTips)
            _ProtocolLine(text: tip),
        ],
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
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              value == null ? '–' : '$value.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF202020).withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF202020).withOpacity(0.6),
                height: 1.4,
              ),
            ),
          ),
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
    return GestureDetector(
      onTap: measurement == null
          ? null
          : () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: measurement == null
            ? Text('No readings yet.', style: GoogleFonts.inter(
                color: const Color(0xFF202020).withOpacity(0.5), fontSize: 13,
              ))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _primaryText(measurement),
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF202020),
                          ),
                        ),
                      ),
                      _StatusBadge(status: measurement.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _capturedText(measurement.capturedAt),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF202020).withOpacity(0.45),
                    ),
                  ),
                  if (_expanded) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5EFE6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(measurement.toLLMRecord()),
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF202020).withOpacity(0.6)),
                      ),
                    ),
                  ],
                ],
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: progress,
              color: const Color(0xFFA11F2B),
              backgroundColor: const Color(0xFFD9D0C7),
              strokeWidth: 4,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '${(progress * 100).round()}% captured',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF202020),
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFA11F2B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFA11F2B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D0C7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: const Color(0xFF202020).withOpacity(0.5)),
          const SizedBox(width: 12),
          Text(
            'Not supported on this device.',
            style: GoogleFonts.inter(
              color: const Color(0xFF202020).withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.measurement});

  final BiometricMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_iconFor(measurement.status),
              size: 20,
              color: measurement.status == MeasurementStatus.ok
                  ? const Color(0xFF34C759)
                  : Colors.orange.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _primaryText(measurement),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: const Color(0xFF202020),
              ),
            ),
          ),
          Text(
            _capturedText(measurement.capturedAt),
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF202020).withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MeasurementStatus status;

  @override
  Widget build(BuildContext context) {
    final bool isOk = status == MeasurementStatus.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOk
            ? const Color(0xFF34C759).withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.name,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isOk ? const Color(0xFF34C759) : Colors.orange.shade700,
        ),
      ),
    );
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
