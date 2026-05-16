import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Debug-only profiler. Every public method is a no-op in release mode
/// (guarded by [kReleaseMode]) so the Dart tree-shaker drops the bodies.
///
/// API:
///   Profiler.span('name', () async => ...);
///   Profiler.spanSync('name', () => ...);
///   Profiler.event('name', data: {...});
///   Profiler.count('name', 1);
///   await Profiler.exportJson(label: 'autosave');
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

  /// Forces the session-start timestamp to "now". Call from `main()` so the
  /// JSON's `started_at` reflects bootstrap rather than the first event read.
  static void markSessionStart() {
    if (kReleaseMode) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<T> span<T>(String name, Future<T> Function() body) async {
    if (kReleaseMode) return body();
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
    if (kReleaseMode) return body();
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
    if (kReleaseMode) return;
    try {
      _agg.recordSpan(name, durationMs, rssDeltaBytes);
    } catch (_) {}
  }

  static void event(String name, {Map<String, Object?>? data}) {
    if (kReleaseMode) return;
    try {
      _agg.recordEvent(name, data);
    } catch (_) {}
  }

  static void count(String name, [int delta = 1]) {
    if (kReleaseMode) return;
    try {
      _agg.recordCount(name, delta);
    } catch (_) {}
  }

  static void reset() {
    if (kReleaseMode) return;
    try {
      _agg.reset();
    } catch (_) {}
  }

  /// Writes the current session report to a JSON file under the app
  /// documents dir. Returns the path, or null on any failure.
  static Future<String?> exportJson({String? label}) async {
    if (kReleaseMode) return null;
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

  // ── Internal ──────────────────────────────────────────────────────────────

  static int _safeRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}

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

  void reset() {
    _spans.clear();
    _counters.clear();
    _events.clear();
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
      },
      'spans': spans,
      'events': _events.map((e) => e.toJson()).toList(),
      'counters': _counters,
    };
  }
}
