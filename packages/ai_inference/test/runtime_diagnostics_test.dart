import 'package:ai_inference/src/runtime_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts the selected Android CPU variant from process maps', () {
    const maps = '''
7a100000-7a200000 r-xp 00000000 00:00 0 /data/libggml-base.so
7b100000-7b200000 r-xp 00000000 00:00 0 /data/libggml-cpu-android_armv8.6_1.so
''';

    expect(parseLoadedCpuVariant(maps), 'android_armv8.6_1');
  });

  test('returns null when no variant module is mapped', () {
    expect(parseLoadedCpuVariant('/data/libggml-cpu.so'), isNull);
  });
}
