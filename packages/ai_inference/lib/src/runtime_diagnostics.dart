import 'dart:io';

/// Extracts the selected llamadart Android CPU module from `/proc/self/maps`.
///
/// Full CPU-profile bundles contain several `libggml-cpu-android_arm*.so`
/// files. llamadart loads the highest-scoring compatible module, and the
/// selected filename remains visible in the process map after initialization.
String? parseLoadedCpuVariant(String processMaps) {
  final match = RegExp(
    r'libggml-cpu-(android_armv[0-9._]+)\.so',
  ).firstMatch(processMaps);
  return match?.group(1);
}

/// Best-effort lookup of the CPU module selected by the native runtime.
String? readLoadedCpuVariant() {
  if (!Platform.isAndroid) return null;
  try {
    final maps = File('/proc/self/maps');
    if (!maps.existsSync()) return null;
    return parseLoadedCpuVariant(maps.readAsStringSync());
  } catch (_) {
    return null;
  }
}
