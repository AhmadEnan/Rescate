import 'dart:convert';

import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Profiler.reset();
    Profiler.markSessionStart();
  });

  tearDown(() {
    Profiler.reset();
  });

  test('kProfilerEnabled is a compile-time constant', () {
    expect(kProfilerEnabled, isA<bool>());
  });

  test('span and spanSync record aggregates', () async {
    await Profiler.span('test.async', () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    Profiler.spanSync('test.sync', () {
      for (var i = 0; i < 1000; i++) {
        i.isEven;
      }
    });

    final report = Profiler.snapshot();
    final spans = report['spans'] as List<dynamic>;
    final asyncSpan = spans
        .cast<Map<String, Object?>>()
        .firstWhere((s) => s['name'] == 'test.async');
    final syncSpan = spans
        .cast<Map<String, Object?>>()
        .firstWhere((s) => s['name'] == 'test.sync');

    expect(asyncSpan['count'], 1);
    expect(asyncSpan['total_ms'], greaterThanOrEqualTo(5));
    expect(syncSpan['count'], 1);
  });

  test('recordSpan, event and count are recorded', () {
    Profiler.recordSpan('test.manual', 42);
    Profiler.event('test.event', data: <String, Object?>{'k': 'v'});
    Profiler.count('test.counter', 3);
    Profiler.count('test.counter', 2);

    final report = Profiler.snapshot();
    final spans = report['spans'] as List<dynamic>;
    final manual = spans
        .cast<Map<String, Object?>>()
        .firstWhere((s) => s['name'] == 'test.manual');
    expect(manual['total_ms'], 42);

    final events = report['events'] as List<dynamic>;
    expect(events, hasLength(1));
    expect(
      (events.first as Map<String, Object?>)['name'],
      'test.event',
    );

    final counters = report['counters'] as Map<String, Object?>;
    expect(counters['test.counter'], 5);
  });

  test('trace records nested steps with wall time and ops', () async {
    final trace = Profiler.openTrace('test.pipeline');
    final first = trace?.begin('step.a');
    first?.op(3);
    final nested = trace?.begin('step.b');
    nested?.op(7);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    nested?.end();
    first?.op(2); // ops after a child closed still count on the open parent
    first?.end();
    trace?.end();

    expect(trace, isNotNull);
    final report = Profiler.snapshot();
    final traces = report['traces'] as List<dynamic>;
    expect(traces, hasLength(1));

    final json = traces.first as Map<String, Object?>;
    expect(json['name'], 'test.pipeline');
    expect(json['wall_ms'], greaterThanOrEqualTo(5));

    final steps = json['steps'] as List<dynamic>;
    expect(steps, hasLength(1));
    final a = steps.first as Map<String, Object?>;
    expect(a['name'], 'step.a');
    expect(a['ops'], 5);
    final children = a['children'] as List<dynamic>;
    expect(children, hasLength(1));
    final b = children.first as Map<String, Object?>;
    expect(b['name'], 'step.b');
    expect(b['ops'], 7);
    expect(b['wall_ms'], greaterThanOrEqualTo(4));
    expect(b['ops_per_sec'], isA<int>());
  });

  test('trace ops count against the root when no step is open', () {
    final trace = Profiler.openTrace('test.rootops');
    trace?.op(5);
    trace?.op(2);
    trace?.end();

    final report = Profiler.snapshot();
    final json = (report['traces'] as List<dynamic>).first
        as Map<String, Object?>;
    expect(json['ops'], 7);
  });

  test('unclosed steps are auto-closed when the trace ends', () {
    final trace = Profiler.openTrace('test.leak');
    trace?.begin('step.unclosed')?.op(1);
    trace?.end(); // never called end() on the step

    final report = Profiler.snapshot();
    final json = (report['traces'] as List<dynamic>).first
        as Map<String, Object?>;
    final steps = json['steps'] as List<dynamic>;
    expect(steps, hasLength(1));
    final step = steps.first as Map<String, Object?>;
    expect(step['name'], 'step.unclosed');
    expect(step['wall_ms'], greaterThanOrEqualTo(0));
  });

  test('trace data and events appear in the report', () {
    final trace = Profiler.openTrace(
      'test.data',
      data: <String, Object?>{'input': 'x'},
    );
    trace?.event('hit', data: <String, Object?>{'n': 1});
    trace?.setData('derived', 42);
    trace?.end();

    final json = (Profiler.snapshot()['traces'] as List<dynamic>).first
        as Map<String, Object?>;
    expect(json['data'], <String, Object?>{'input': 'x', 'derived': 42});
    expect(json['events'], hasLength(1));
  });

  test('exported report is valid JSON and matches snapshot', () async {
    Profiler.spanSync('test.sync', () {});
    final report = Profiler.snapshot();
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    expect(decoded['session'], isNotNull);
    expect(decoded['spans'], isA<List<dynamic>>());
    expect(decoded['counters'], isA<Map<String, Object?>>());
    expect(decoded['traces'], isA<List<dynamic>>());
  });

  test('reset clears aggregates and traces', () {
    Profiler.spanSync('test.sync', () {});
    final trace = Profiler.openTrace('test.pipeline');
    trace?.end();
    Profiler.reset();

    final report = Profiler.snapshot();
    expect(report['spans'], isEmpty);
    expect(report['traces'], isEmpty);
    expect(report['counters'], isEmpty);
  });
}
