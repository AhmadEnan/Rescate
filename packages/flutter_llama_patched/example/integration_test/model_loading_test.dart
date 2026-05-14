import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_llama/flutter_llama.dart';
import '../lib/utils/model_downloader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Model Loading Integration Tests', () {
    late FlutterLlama llama;

    setUp(() {
      llama = FlutterLlama.instance;
    });

    tearDown(() async {
      // Cleanup: unload model after each test
      try {
        if (llama.isModelLoaded) {
          await llama.unloadModel();
        }
      } catch (e) {
        print('Error during cleanup: $e');
      }
    });

    testWidgets('should download and load q2_k model', (
      WidgetTester tester,
    ) async {
      print('Starting model download test...');

      // Download model if not already present
      String? modelPath = await ModelDownloader.getModelPath('braindler-q2_k');

      if (modelPath == null) {
        print('Model not found, downloading...');
        modelPath = await ModelDownloader.downloadModel(
          'braindler-q2_k',
          onProgress: (progress) {
            print('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
          },
        );
      } else {
        print('Model already exists at: $modelPath');
      }

      expect(modelPath, isNotNull);
      expect(File(modelPath!).existsSync(), isTrue);

      // Load model
      print('Loading model...');
      final config = LlamaConfig(
        modelPath: modelPath,
        nThreads: 4,
        contextSize: 2048,
        useGpu: true,
        verbose: true,
      );

      final result = await llama.loadModel(config);

      expect(result, isTrue);
      expect(llama.isModelLoaded, isTrue);
      expect(llama.modelPath, modelPath);

      print('Model loaded successfully!');
    });

    testWidgets('should load model and get info', (WidgetTester tester) async {
      print('Testing model info...');

      String? modelPath = await ModelDownloader.getModelPath('braindler-q2_k');
      if (modelPath == null) {
        modelPath = await ModelDownloader.downloadModel('braindler-q2_k');
      }

      final config = LlamaConfig(modelPath: modelPath!, verbose: true);

      await llama.loadModel(config);

      final info = await llama.getModelInfo();

      expect(info, isNotNull);
      print('Model info: $info');

      // Verify info contains expected fields
      if (info != null) {
        expect(info.containsKey('modelPath') || info.isNotEmpty, isTrue);
      }
    });

    testWidgets('should handle multiple load/unload cycles', (
      WidgetTester tester,
    ) async {
      print('Testing multiple load/unload cycles...');

      String? modelPath = await ModelDownloader.getModelPath('braindler-q2_k');
      if (modelPath == null) {
        modelPath = await ModelDownloader.downloadModel('braindler-q2_k');
      }

      final config = LlamaConfig(modelPath: modelPath!);

      // Load and unload 3 times
      for (int i = 0; i < 3; i++) {
        print('Cycle ${i + 1}/3: Loading model...');
        final loaded = await llama.loadModel(config);
        expect(loaded, isTrue);
        expect(llama.isModelLoaded, isTrue);

        print('Cycle ${i + 1}/3: Unloading model...');
        await llama.unloadModel();
        expect(llama.isModelLoaded, isFalse);
      }

      print('Multiple cycles completed successfully!');
    });

    testWidgets('should fail gracefully with invalid model path', (
      WidgetTester tester,
    ) async {
      print('Testing invalid model path...');

      final config = LlamaConfig(modelPath: '/invalid/path/to/model.gguf');

      final result = await llama.loadModel(config);

      expect(result, isFalse);
      expect(llama.isModelLoaded, isFalse);

      print('Invalid path handled correctly!');
    });

    testWidgets('should load model with different configurations', (
      WidgetTester tester,
    ) async {
      print('Testing different configurations...');

      String? modelPath = await ModelDownloader.getModelPath('braindler-q2_k');
      if (modelPath == null) {
        modelPath = await ModelDownloader.downloadModel('braindler-q2_k');
      }

      // Test with minimal config
      print('Testing minimal config...');
      var config = LlamaConfig(
        modelPath: modelPath!,
        nThreads: 2,
        contextSize: 512,
      );

      var result = await llama.loadModel(config);
      expect(result, isTrue);
      await llama.unloadModel();

      // Test with maximal config
      print('Testing maximal config...');
      config = LlamaConfig(
        modelPath: modelPath,
        nThreads: 8,
        contextSize: 2048,
        batchSize: 512,
        nGpuLayers: -1, // Use all GPU layers if available
        useGpu: true,
        verbose: true,
      );

      result = await llama.loadModel(config);
      expect(result, isTrue);

      print('Different configurations tested successfully!');
    });
  });

  group('Model Downloader Tests', () {
    testWidgets('should list available models', (WidgetTester tester) async {
      final models = ModelDownloader.getAvailableModels();

      expect(models.isNotEmpty, isTrue);
      expect(models.containsKey('braindler-q2_k'), isTrue);
      expect(models.containsKey('braindler-q4_k_s'), isTrue);

      print('Available models:');
      for (final entry in models.entries) {
        print(
          '  ${entry.key}: ${entry.value.sizeFormatted} (${entry.value.quantization})',
        );
      }
    });

    testWidgets('should check for downloaded models', (
      WidgetTester tester,
    ) async {
      final downloaded = await ModelDownloader.getDownloadedModels();

      print('Downloaded models: ${downloaded.length}');
      for (final model in downloaded) {
        print('  - $model');
      }

      expect(downloaded, isA<List<String>>());
    });

    testWidgets('should get model path if exists', (WidgetTester tester) async {
      final path = await ModelDownloader.getModelPath('braindler-q2_k');

      if (path != null) {
        print('Model path: $path');
        expect(File(path).existsSync(), isTrue);
      } else {
        print('Model not downloaded yet');
      }
    });

    testWidgets('should download small model with progress tracking', (
      WidgetTester tester,
    ) async {
      print('Testing download with progress tracking...');

      // Check if already downloaded
      final existingPath = await ModelDownloader.getModelPath('braindler-q2_k');
      if (existingPath != null) {
        print('Model already downloaded, skipping download test');
        return;
      }

      final progressUpdates = <double>[];

      final modelPath = await ModelDownloader.downloadModel(
        'braindler-q2_k',
        onProgress: (progress) {
          progressUpdates.add(progress);
          if (progress == 1.0 || progressUpdates.length % 10 == 0) {
            print('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
          }
        },
      );

      expect(modelPath, isNotNull);
      expect(File(modelPath).existsSync(), isTrue);
      expect(progressUpdates.isNotEmpty, isTrue);
      expect(progressUpdates.last, greaterThanOrEqualTo(1.0));

      print('Download completed successfully!');
    });
  });
}





