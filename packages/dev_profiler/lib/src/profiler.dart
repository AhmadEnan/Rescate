import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Compile-time master switch for ALL performance monitoring.
///
/// Default: ON in debug/profile builds, OFF in release builds. Override at
/// compile time with a simple flag:
///
///   flutter build apk --dart-define=RESCATE_PROFILER=false   # force OFF
///   flutter build apk --dart-define=RESCATE_PROFILER=true    # force ON
///
/// Because this is a const bool, when `false` the Dart tree-shaker drops the
/// entire profiler body — zero runtime cost, zero binary size impact.
const bool kProfilerEnabled = bool.fromEnvironment(
  'RESCATE_PROFILER',
  defaultValue: !kReleaseMode,
);

/// Debug-only profiler. Every public method is a no-op when
/// [kProfilerEnabled] is false (guarded by the compile-time const above).
///
/// Two measurement layers:
///
/// 1. **Aggregates** — flat, per-name statistics accumulated over the session:
///    ```
///    Profiler.span('rag.search', () => ...);      // async, times body
///    Profiler.spanSync('rag.buildPrompt', ...);   // sync, times body
///    Profiler.recordSpan('name', ms);             // manual, e.g. in streams
///    Profiler.event('llm.ttft', data: {...});     // timestamped event
///    Profiler.count('llm.tokens', n);             // operation counter
///    ```
///
/// 2. **Traces** — one hierarchical record of a single pipeline run (e.g. one
///    LLM chat turn). Each step captures wall time AND an operation counter,
///    so you can read "this phase took 4.2 s for 1,800 ops" per pipeline run:
///    ```
///    final trace = Profiler.openTrace('llm.turn');
///    final decode = trace?.begin('llm.decode');
///    for (...) { decode?.op(1); }        // count operations
///    decode?.end();                      // stop the clock
///    trace?.end();                       // persist into the report
///    ```
///
/// [Profiler.exportJson] writes the full report (session info + aggregates +
/// traces) to `<appDocuments>/profiler/session_<ts>.json`.
///
/// All operations are wrapped in try/catch — a profiler bug never crashes
/// a feature. Memory deltas are best-effort via ProcessInfo.currentRss.
class Profiler {
  Profiler._();

  static final _Aggregates _agg = _Aggregates();
  static int _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
  static DateTime get _sessionStart =>
      DateTime.fromMillisecondsSinceEpoch(_sessionStartMs);
  static const int _maxEvents = 5000;
  static const int _maxTraces = 200;
  static int _nextTraceId = 1;

  /// Forces the session-start timestamp to "now". Call from `main()` so the
  /// JSON's `started_at` reflects bootstrap rather than the first event read.
  static void markSessionStart() {
    if (!kProfilerEnabled) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  // ── Aggregate API ──────────────────────────────────────────────────────────

  static Future<T> span<T>(String name, Future<T> Function() body) async {
    if (!kProfilerEnabled) return body();
    final sw = Stopwatch()..start();
    final rssStart = _safeRss();
    try {
      return await body();
    } finally {
      sw.stop();
      try {
        _agg.recordSpan(name, sw.elapsedMilliseconds, _safeRss() - rssStart);
      } catch (_) {}
    }
  }

  static T spanSync<T>(String name, T Function() body) {
    if (!kProfilerEnabled) return body();
    final sw = Stopwatch()..start();
    final rssStart = _safeRss();
    try {
      return body();
    } finally {
      sw.stop();
      try {
        _agg.recordSpan(name, sw.elapsedMilliseconds, _safeRss() - rssStart);
      } catch (_) {}
    }
  }

  /// Manually record a span. Use when you can't wrap a body in [span] —
  /// e.g. inside an `async*` generator where awaiting the whole stream
  /// inside a closure is impractical. [rssDeltaBytes] may be 0 if unknown.
  static void recordSpan(String name, int durationMs, {int rssDeltaBytes = 0}) {
    if (!kProfilerEnabled) return;
    try {
      _agg.recordSpan(name, durationMs, rssDeltaBytes);
    } catch (_) {}
  }

  static void event(String name, {Map<String, Object?>? data}) {
    if (!kProfilerEnabled) return;
    try {
      _agg.recordEvent(name, data);
    } catch (_) {}
  }

  static void count(String name, [int delta = 1]) {
    if (!kProfilerEnabled) return;
    try {
      _agg.recordCount(name, delta);
    } catch (_) {}
  }

  static void reset() {
    if (!kProfilerEnabled) return;
    try {
      _agg.reset();
    } catch (_) {}
  }

  /// In-memory snapshot of the full report (aggregates + traces). Useful for
  /// tests and for callers that want the JSON without writing a file.
  static Map<String, Object?> snapshot() {
    if (!kProfilerEnabled) return <String, Object?>{};
    try {
      return _agg.snapshot(sessionStart: _sessionStart);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  // ── Trace API ──────────────────────────────────────────────────────────────

  /// Opens a named pipeline trace and returns a handle to record steps into.
  ///
  /// Returns `null` when the profiler is disabled or an error occurs — callers
  /// must null-check before use (see example in the class docs).
  static TraceHandle? openTrace(String name, {Map<String, Object?>? data}) {
    if (!kProfilerEnabled) return null;
    try {
      final t = _agg.openTrace(name, data);
      if (t == null) return null;
      t.id = _nextTraceId++;
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Convenience wrapper around [openTrace]: runs [body] with a fresh trace
  /// and finalizes it afterwards (always — even on error).
  static Future<T?> trace<T>(
    String name,
    Future<T?> Function(TraceHandle? handle) body, {
    Map<String, Object?>? data,
  }) async {
    final handle = openTrace(name, data: data);
    try {
      return await body(handle);
    } finally {
      handle?.end();
    }
  }

  static T? traceSync<T>(
    String name,
    T? Function(TraceHandle? handle) body, {
    Map<String, Object?>? data,
  }) {
    final handle = openTrace(name, data: data);
    try {
      return body(handle);
    } finally {
      handle?.end();
    }
  }

  /// Writes the current session report to a JSON file under the app
  /// documents dir. Returns the path, or null on any failure.
  static Future<String?> exportJson({String? label}) async {
    if (!kProfilerEnabled) return null;
    try {
      final report = _agg.snapshot(sessionStart: _sessionStart);
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}/profiler');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final suffix = (label == null || label.isEmpty) ? '' : '_$label';
      final file = File('${outDir.path}/session_$ts$suffix.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      debugPrint('[Profiler] Exported ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[Profiler] exportJson failed: $e');
      return null;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static int _safeRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}

// ── Traces ────────────────────────────────────────────────────────────────────

/// One step of a [TraceHandle] pipeline run.
///
/// Records wall time from [TraceHandle.begin] to [end], plus an operation
/// counter fed via [op] (e.g. tokens decoded, samples filtered, DB rows read).
/// Steps nest: children begun while this step is open become its children.
class TraceStep {
  TraceStep._(this.name, this._rssStart, this._handle)
      : _sw = Stopwatch()..start();

  final String name;
  final TraceHandle _handle;
  final int _rssStart;
  final Stopwatch _sw;
  final List<TraceStep> _children = <TraceStep>[];
  TraceStep? _parent;
  final Map<String, Object?> data = <String, Object?>{};

  /// Number of operations performed inside this step (fed via [op]).
  int ops = 0;

  int _wallMs = -1;
  int _rssDelta = 0;
  bool _closed = false;

  /// Wall time of the step in ms once [end] has been called, -1 otherwise.
  int get wallMs => _wallMs;

  /// RSS delta in bytes across the step (best-effort, may be 0).
  int get rssDeltaBytes => _rssDelta;

  /// Counts [n] (default 1) operations on this step. Cheap — safe in hot loops.
  void op([int n = 1]) {
    if (_closed) return;
    ops += n;
  }

  /// Attaches an extra data field to the step (e.g. derived throughput).
  void setData(String key, Object? value) {
    if (_closed) return;
    data[key] = value;
  }

  /// Stops the clock and closes the step. Any children still open are closed
  /// automatically with their elapsed time.
  void end() {
    _handle._closeStep(this);
  }
}

/// Handle for a single pipeline trace. Created by [Profiler.openTrace];
/// `null` when profiling is disabled — always null-check before use.
///
/// ```
/// final trace = Profiler.openTrace('llm.turn');
/// final decode = trace?.begin('llm.decode');
/// for (final t in stream) { decode?.op(1); }
/// decode?.end();
/// trace?.end();
/// ```
class TraceHandle {
  TraceHandle._(this.name, this.startedAtMs, this._rssStart, Map<String, Object?>? data)
      : data = <String, Object?>{...?data};

  final String name;
  final int startedAtMs;
  final int _rssStart;
  final Map<String, Object?> data;
  final List<TraceStep> _roots = <TraceStep>[];
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  final Stopwatch _sw = Stopwatch()..start();

  late int id;
  TraceStep? _active;
  int _rootOps = 0;
  int _wallMs = 0;
  int _rssDeltaBytes = 0;
  bool _ended = false;

  /// Begins a step with [name] as a child of the current open step (or of the
  /// trace root). Returns the step, or `null` if the trace is already ended.
  TraceStep? begin(String name) {
    if (_ended) return null;
    final node = TraceStep._(name, Profiler._safeRss(), this);
    final active = _active;
    if (active == null) {
      _roots.add(node);
    } else {
      active._children.add(node);
      node._parent = active;
    }
    _active = node;
    return node;
  }

  /// Counts operations against the current open step, or the trace root when
  /// no step is open.
  void op([int n = 1]) {
    if (_ended) return;
    final active = _active;
    if (active != null) {
      active.op(n);
    } else {
      _rootOps += n;
    }
  }

  /// Records a timestamped event relative to the trace start.
  void event(String name, {Map<String, Object?>? data}) {
    if (_ended) return;
    if (events.length >= 256) events.removeAt(0);
    events.add(<String, Object?>{
      'name': name,
      't_ms': _sw.elapsedMilliseconds,
      if (data != null) 'data': data,
    });
  }

  /// Attaches an extra data field to the trace (e.g. native llama.cpp timings).
  void setData(String key, Object? value) {
    if (_ended) return;
    data[key] = value;
  }

  /// Finalizes the trace: closes any open steps, stops the clock, and persists
  /// the run into the session report.
  void end() {
    if (_ended) return;
    // Close any steps left open (e.g. an exception unwound the generator
    // mid-step) so the tree always carries wall times.
    for (final root in _roots) {
      if (!root._closed) _closeStep(root);
    }
    _ended = true;
    _sw.stop();
    _wallMs = _sw.elapsedMilliseconds;
    _rssDeltaBytes = Profiler._safeRss() - _rssStart;
    Profiler._agg.finishTrace(this);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _closeStep(TraceStep node) {
    if (_ended) return;
    // Close unclosed children first (recursively) so the tree stays consistent.
    for (final child in node._children) {
      if (!child._closed) _closeStep(child);
    }
    if (!node._closed) {
      node._closed = true;
      node._sw.stop();
      node._wallMs = node._sw.elapsedMilliseconds;
      node._rssDelta = Profiler._safeRss() - node._rssStart;
    }
    // Pop the active-pointer past any step this subtree just closed.
    while (_active != null && _active!._closed) {
      _active = _active!._parent;
    }
  }
}

// ── Aggregates ────────────────────────────────────────────────────────────────

class _SpanStat {
  int count = 0;
  int totalMs = 0;
  int minMs = 1 << 30;
  int maxMs = 0;
  int rssDeltaSum = 0;
  int rssDeltaMax = 0;
  final List<int> samplesMs = <int>[];

  void add(int ms, int rssDelta) {
    count++;
    totalMs += ms;
    if (ms < minMs) minMs = ms;
    if (ms > maxMs) maxMs = ms;
    rssDeltaSum += rssDelta;
    if (rssDelta > rssDeltaMax) rssDeltaMax = rssDelta;
    if (samplesMs.length < 200) samplesMs.add(ms);
  }

  Map<String, Object?> toJson(String name) => <String, Object?>{
        'name': name,
        'count': count,
        'total_ms': totalMs,
        'min_ms': count == 0 ? 0 : minMs,
        'max_ms': maxMs,
        'mean_ms': count == 0 ? 0 : (totalMs / count).round(),
        'rss_delta_bytes_sum': rssDeltaSum,
        'rss_delta_bytes_max': rssDeltaMax,
        'samples_ms': samplesMs,
      };
}

class _Event {
  _Event(this.name, this.tMsSinceStart, this.data);
  final String name;
  final int tMsSinceStart;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        't_ms_since_session': tMsSinceStart,
        if (data != null) 'data': data,
      };
}

class _Aggregates {
  final Map<String, _SpanStat> _spans = <String, _SpanStat>{};
  final Map<String, int> _counters = <String, int>{};
  final List<_Event> _events = <_Event>[];
  final List<TraceHandle> _traces = <TraceHandle>[];

  void recordSpan(String name, int ms, int rssDelta) {
    _spans.putIfAbsent(name, () => _SpanStat()).add(ms, rssDelta);
  }

  void recordEvent(String name, Map<String, Object?>? data) {
    final t = DateTime.now().millisecondsSinceEpoch - Profiler._sessionStartMs;
    if (_events.length >= Profiler._maxEvents) {
      _events.removeAt(0);
    }
    _events.add(_Event(name, t, data));
  }

  void recordCount(String name, int delta) {
    _counters[name] = (_counters[name] ?? 0) + delta;
  }

  TraceHandle? openTrace(String name, Map<String, Object?>? data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TraceHandle._(
      name,
      now,
      Profiler._safeRss(),
      data,
    );
  }

  void finishTrace(TraceHandle trace) {
    _traces.add(trace);
    if (_traces.length > Profiler._maxTraces) {
      _traces.removeAt(0);
    }
  }

  void reset() {
    _spans.clear();
    _counters.clear();
    _events.clear();
    _traces.clear();
  }

  Map<String, Object?> snapshot({required DateTime sessionStart}) {
    final spans = _spans.entries.map((e) => e.value.toJson(e.key)).toList()
      ..sort((a, b) =>
          ((b['total_ms'] as int)).compareTo(a['total_ms'] as int));
    return <String, Object?>{
      'session': <String, Object?>{
        'started_at': sessionStart.toIso8601String(),
        'ended_at': DateTime.now().toIso8601String(),
        'build_mode': kDebugMode
            ? 'debug'
            : (kProfileMode ? 'profile' : 'release'),
        'profiler_enabled': kProfilerEnabled,
      },
      'spans': spans,
      'events': _events.map((e) => e.toJson()).toList(),
      'counters': _counters,
      'traces': _traces.map(_traceToJson).toList(),
    };
  }

  static Map<String, Object?> _stepToJson(TraceStep s) {
    final int ms = s._wallMs;
    return <String, Object?>{
      'name': s.name,
      'wall_ms': ms,
      'ops': s.ops,
      if (ms > 0 && s.ops > 0) 'ops_per_sec': (s.ops * 1000 / ms).round(),
      'rss_delta_bytes': s._rssDelta,
      if (s.data.isNotEmpty) 'data': s.data,
      if (s._children.isNotEmpty)
        'children': s._children.map(_stepToJson).toList(),
    };
  }

  static Map<String, Object?> _traceToJson(TraceHandle t) => <String, Object?>{
        'id': t.id,
        'name': t.name,
        'started_at_ms_since_session':
            t.startedAtMs - Profiler._sessionStartMs,
        'wall_ms': t._wallMs,
        'ops': t._rootOps,
        'rss_delta_bytes': t._rssDeltaBytes,
        if (t.data.isNotEmpty) 'data': t.data,
        if (t.events.isNotEmpty) 'events': t.events,
        'steps': t._roots.map(_stepToJson).toList(),
      };
}
