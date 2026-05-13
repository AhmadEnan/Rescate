import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class MicSource {
  MicSource() : _samples = null;

  MicSource.forTesting(Future<List<double>> samples) : _samples = samples;

  final Future<List<double>>? _samples;

  Future<List<double>> samples({
    Duration duration = const Duration(seconds: 60),
    void Function(double)? onProgress,
    Future<void>? cancelToken,
  }) async {
    final Future<List<double>>? injected = _samples;
    if (injected != null) {
      return injected;
    }
    final AudioRecorder recorder = AudioRecorder();
    final Stream<Uint8List> stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
      ),
    );
    final List<double> out = <double>[];
    final Stopwatch sw = Stopwatch()..start();
    final StreamSubscription<Uint8List> sub = stream.listen((Uint8List chunk) {
      for (int i = 0; i + 1 < chunk.length; i += 2) {
        int sample = chunk[i] | (chunk[i + 1] << 8);
        if (sample >= 0x8000) {
          sample -= 0x10000;
        }
        out.add(sample / 32768.0);
      }
      onProgress?.call(
        (sw.elapsedMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
      );
    });
    if (cancelToken != null) {
      await Future.any(<Future<void>>[
        Future<void>.delayed(duration),
        cancelToken,
      ]);
    } else {
      await Future<void>.delayed(duration);
    }
    await sub.cancel();
    await recorder.stop();
    await recorder.dispose();
    return out;
  }
}
