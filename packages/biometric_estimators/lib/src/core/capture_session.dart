import 'dart:async';

import 'diagnostic_event.dart';

class CaptureSession {
  CaptureSession();

  final StreamController<double> _progress =
      StreamController<double>.broadcast();
  final StreamController<double> _rawSignal =
      StreamController<double>.broadcast();
  final StreamController<DiagnosticEvent> _diagnostics =
      StreamController<DiagnosticEvent>.broadcast();
  final Completer<void> _cancel = Completer<void>();

  // Replay buffers so widgets that subscribe late can catch up on all samples
  // emitted before they were inserted into the widget tree.
  final List<double> _rawBuffer = <double>[];
  final List<DiagnosticEvent> _diagnosticsBuffer = <DiagnosticEvent>[];
  static const int _rawBufferMax = 1200; // 60 s × 20 Hz

  Stream<double> get progress => _progress.stream;

  /// Live stream of downsampled raw sensor values (~20 Hz).
  Stream<double> get rawSignal => _rawSignal.stream;

  /// All raw samples emitted so far — used by the chart widget to catch up
  /// if it subscribes after capture has already started.
  List<double> get rawSampleBuffer =>
      List<double>.unmodifiable(_rawBuffer);

  /// Stage-by-stage DSP diagnostic events.
  Stream<DiagnosticEvent> get diagnostics => _diagnostics.stream;

  /// All diagnostic events emitted so far — used by the panel to catch up.
  List<DiagnosticEvent> get diagnosticBuffer =>
      List<DiagnosticEvent>.unmodifiable(_diagnosticsBuffer);

  Future<void> get cancelToken => _cancel.future;
  bool get isCancelled => _cancel.isCompleted;

  void emitProgress(double frac) {
    if (!_progress.isClosed) {
      _progress.add(frac.clamp(0.0, 1.0));
    }
  }

  void emitRawSample(double value) {
    _rawBuffer.add(value);
    if (_rawBuffer.length > _rawBufferMax) {
      _rawBuffer.removeAt(0);
    }
    if (!_rawSignal.isClosed) {
      _rawSignal.add(value);
    }
  }

  void emitDiagnostic(DiagnosticEvent event) {
    _diagnosticsBuffer.add(event);
    if (!_diagnostics.isClosed) {
      _diagnostics.add(event);
    }
  }

  void cancel() {
    if (!_cancel.isCompleted) {
      _cancel.complete();
    }
  }

  Future<void> close() async {
    await Future.wait(<Future<void>>[
      _progress.close(),
      _rawSignal.close(),
      _diagnostics.close(),
    ]);
  }
}
