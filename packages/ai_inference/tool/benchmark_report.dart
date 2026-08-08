import 'dart:convert';
import 'dart:io';

import '../lib/src/benchmark.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/benchmark_report.dart '
      '<profiler-report.json> [benchmark-report.json]',
    );
    exitCode = 64;
    return;
  }

  final input = File(arguments[0]);
  if (!await input.exists()) {
    stderr.writeln('Profiler report not found: ${input.path}');
    exitCode = 66;
    return;
  }

  var contents = await input.readAsString();
  // Windows pulls may preserve the UTF-8 BOM emitted by the profiler file.
  if (contents.startsWith('\uFEFF')) {
    contents = contents.substring(1);
  }
  final decoded = jsonDecode(contents);
  if (decoded is! Map) {
    stderr.writeln('Profiler report root must be a JSON object.');
    exitCode = 65;
    return;
  }

  final snapshot = decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  final report = LlmBenchmarkReport.fromProfilerSnapshot(snapshot);
  final output = File(
    arguments.length == 2 ? arguments[1] : 'benchmark_report.json',
  );
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  stdout.writeln('Wrote ${output.path}');
}
