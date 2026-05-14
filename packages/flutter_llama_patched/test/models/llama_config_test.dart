import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() {
  group('LlamaConfig', () {
    test('creates config with required parameters', () {
      const config = LlamaConfig(
        modelPath: '/path/to/model.gguf',
      );

      expect(config.modelPath, '/path/to/model.gguf');
      expect(config.nThreads, 4);
      expect(config.nGpuLayers, 0);
      expect(config.contextSize, 2048);
      expect(config.batchSize, 512);
      expect(config.useGpu, true);
      expect(config.verbose, false);
    });

    test('creates config with custom parameters', () {
      const config = LlamaConfig(
        modelPath: '/path/to/custom.gguf',
        nThreads: 8,
        nGpuLayers: 32,
        contextSize: 4096,
        batchSize: 1024,
        useGpu: false,
        verbose: true,
      );

      expect(config.modelPath, '/path/to/custom.gguf');
      expect(config.nThreads, 8);
      expect(config.nGpuLayers, 32);
      expect(config.contextSize, 4096);
      expect(config.batchSize, 1024);
      expect(config.useGpu, false);
      expect(config.verbose, true);
    });

    test('toMap converts config to map correctly', () {
      const config = LlamaConfig(
        modelPath: '/test/model.gguf',
        nThreads: 6,
        nGpuLayers: 16,
        contextSize: 3072,
        batchSize: 768,
        useGpu: true,
        verbose: true,
      );

      final map = config.toMap();

      expect(map['modelPath'], '/test/model.gguf');
      expect(map['nThreads'], 6);
      expect(map['nGpuLayers'], 16);
      expect(map['contextSize'], 3072);
      expect(map['batchSize'], 768);
      expect(map['useGpu'], true);
      expect(map['verbose'], true);
    });

    test('toString returns formatted string', () {
      const config = LlamaConfig(
        modelPath: '/test/model.gguf',
        nThreads: 4,
      );

      final str = config.toString();

      expect(str, contains('LlamaConfig'));
      expect(str, contains('modelPath: /test/model.gguf'));
      expect(str, contains('nThreads: 4'));
      expect(str, contains('contextSize: 2048'));
    });

    test('configs with same values are equal', () {
      const config1 = LlamaConfig(
        modelPath: '/path/to/model.gguf',
        nThreads: 4,
      );

      const config2 = LlamaConfig(
        modelPath: '/path/to/model.gguf',
        nThreads: 4,
      );

      // Note: Since LlamaConfig doesn't override == operator,
      // this tests that configs are created consistently
      expect(config1.toMap().toString(), config2.toMap().toString());
    });

    test('handles GPU layer configurations', () {
      const cpuOnly = LlamaConfig(
        modelPath: '/model.gguf',
        nGpuLayers: 0,
        useGpu: false,
      );

      const allGpu = LlamaConfig(
        modelPath: '/model.gguf',
        nGpuLayers: -1,
        useGpu: true,
      );

      const partialGpu = LlamaConfig(
        modelPath: '/model.gguf',
        nGpuLayers: 20,
        useGpu: true,
      );

      expect(cpuOnly.nGpuLayers, 0);
      expect(cpuOnly.useGpu, false);

      expect(allGpu.nGpuLayers, -1);
      expect(allGpu.useGpu, true);

      expect(partialGpu.nGpuLayers, 20);
      expect(partialGpu.useGpu, true);
    });
  });
}





