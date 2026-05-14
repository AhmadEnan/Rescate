import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

// Import the downloader helper
import '../../test/helpers/ollama_model_downloader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Ollama Model Integration Tests', () {
    late String testModelPath;
    late Directory tempDir;
    final FlutterLlama llama = FlutterLlama.instance;

    setUpAll(() async {
      // Get temporary directory for test models
      tempDir = await getTemporaryDirectory();
      final modelsDir = Directory(path.join(tempDir.path, 'test_models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      print('[Test] Models directory: ${modelsDir.path}');

      // Try to get model from Ollama installation first
      print('[Test] Checking for Ollama installation...');
      final ollamaModelPath = await OllamaModelDownloader.getOllamaModelPath(
        'braindler',
      );

      if (ollamaModelPath != null && await File(ollamaModelPath).exists()) {
        print('[Test] Found existing Ollama model: $ollamaModelPath');
        testModelPath = ollamaModelPath;
      } else {
        // Try to pull using Ollama CLI
        print('[Test] Attempting to pull model using Ollama CLI...');
        try {
          testModelPath = await OllamaModelDownloader.pullModelWithOllama(
            model: 'nativemind/braindler:q2_k',
            destinationPath: modelsDir.path,
          );
          print('[Test] Model pulled successfully: $testModelPath');
        } catch (e) {
          print('[Test] Failed to pull with Ollama CLI: $e');
          print('[Test] Skipping tests - Ollama not available');
          testModelPath = '';
        }
      }
    });

    tearDownAll(() async {
      // Cleanup: unload model
      try {
        await llama.unloadModel();
      } catch (e) {
        print('[Test] Cleanup error: $e');
      }
    });

    testWidgets('downloads and validates GGUF model', (
      WidgetTester tester,
    ) async {
      // Skip if no model available
      if (testModelPath.isEmpty) {
        print('[Test] Skipping - no model available');
        return;
      }

      final isValid = await OllamaModelDownloader.isValidGGUFFile(
        testModelPath,
      );
      expect(
        isValid,
        true,
        reason: 'Downloaded file should be valid GGUF format',
      );
    }, skip: testModelPath.isEmpty);

    testWidgets('loads Ollama model successfully', (WidgetTester tester) async {
      if (testModelPath.isEmpty) {
        print('[Test] Skipping - no model available');
        return;
      }

      print('[Test] Loading model from: $testModelPath');

      final config = LlamaConfig(
        modelPath: testModelPath,
        nThreads: 2,
        contextSize: 512,
        verbose: true,
      );

      final result = await llama.loadModel(config);

      expect(result, true, reason: 'Model should load successfully');
      expect(llama.isModelLoaded, true);
      expect(llama.isInitialized, true);
      expect(llama.modelPath, testModelPath);
    }, skip: testModelPath.isEmpty);

    testWidgets(
      'generates text with loaded Ollama model',
      (WidgetTester tester) async {
        if (testModelPath.isEmpty) {
          print('[Test] Skipping - no model available');
          return;
        }

        // Ensure model is loaded
        if (!llama.isModelLoaded) {
          final config = LlamaConfig(
            modelPath: testModelPath,
            nThreads: 2,
            contextSize: 512,
          );
          await llama.loadModel(config);
        }

        print('[Test] Generating text...');

        const params = GenerationParams(
          prompt: 'Hello',
          maxTokens: 50,
          temperature: 0.7,
        );

        final response = await llama.generate(params);

        expect(response, isNotNull);
        expect(
          response.text,
          isNotEmpty,
          reason: 'Generated text should not be empty',
        );
        expect(
          response.tokensGenerated,
          greaterThan(0),
          reason: 'Should generate at least one token',
        );

        print('[Test] Generated: "${response.text}"');
        print(
          '[Test] Tokens: ${response.tokensGenerated}, Time: ${response.generationTimeMs}ms',
        );
        print(
          '[Test] Speed: ${response.tokensPerSecond.toStringAsFixed(2)} tok/s',
        );
      },
      skip: testModelPath.isEmpty,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets('retrieves model info', (WidgetTester tester) async {
      if (testModelPath.isEmpty) {
        print('[Test] Skipping - no model available');
        return;
      }

      // Ensure model is loaded
      if (!llama.isModelLoaded) {
        final config = LlamaConfig(
          modelPath: testModelPath,
          nThreads: 2,
          contextSize: 512,
        );
        await llama.loadModel(config);
      }

      final info = await llama.getModelInfo();

      expect(info, isNotNull);
      print('[Test] Model info: $info');
    }, skip: testModelPath.isEmpty);

    testWidgets(
      'generates multiple responses sequentially',
      (WidgetTester tester) async {
        if (testModelPath.isEmpty) {
          print('[Test] Skipping - no model available');
          return;
        }

        // Ensure model is loaded
        if (!llama.isModelLoaded) {
          final config = LlamaConfig(
            modelPath: testModelPath,
            nThreads: 2,
            contextSize: 512,
          );
          await llama.loadModel(config);
        }

        final prompts = ['Hi', 'Test', 'Hello'];
        final responses = <LlamaResponse>[];

        for (final prompt in prompts) {
          print('[Test] Generating for prompt: "$prompt"');

          final params = GenerationParams(
            prompt: prompt,
            maxTokens: 30,
            temperature: 0.7,
          );

          final response = await llama.generate(params);
          responses.add(response);

          expect(response.text, isNotEmpty);
          print('[Test] Response: "${response.text}"');
        }

        expect(responses.length, prompts.length);
      },
      skip: testModelPath.isEmpty,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'handles different generation parameters',
      (WidgetTester tester) async {
        if (testModelPath.isEmpty) {
          print('[Test] Skipping - no model available');
          return;
        }

        // Ensure model is loaded
        if (!llama.isModelLoaded) {
          final config = LlamaConfig(
            modelPath: testModelPath,
            nThreads: 2,
            contextSize: 512,
          );
          await llama.loadModel(config);
        }

        // Test with different temperatures
        final temps = [0.1, 0.5, 0.9];

        for (final temp in temps) {
          print('[Test] Testing temperature: $temp');

          final params = GenerationParams(
            prompt: 'Test',
            maxTokens: 20,
            temperature: temp,
          );

          final response = await llama.generate(params);
          expect(response.text, isNotEmpty);
          print('[Test] Temp $temp result: "${response.text}"');
        }
      },
      skip: testModelPath.isEmpty,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    testWidgets('unloads model successfully', (WidgetTester tester) async {
      if (testModelPath.isEmpty) {
        print('[Test] Skipping - no model available');
        return;
      }

      // Ensure model is loaded
      if (!llama.isModelLoaded) {
        final config = LlamaConfig(
          modelPath: testModelPath,
          nThreads: 2,
          contextSize: 512,
        );
        await llama.loadModel(config);
      }

      await llama.unloadModel();

      expect(llama.isModelLoaded, false);
      expect(llama.modelPath, null);
    }, skip: testModelPath.isEmpty);

    testWidgets('fails to generate after unloading model', (
      WidgetTester tester,
    ) async {
      if (testModelPath.isEmpty) {
        print('[Test] Skipping - no model available');
        return;
      }

      // Ensure model is unloaded
      if (llama.isModelLoaded) {
        await llama.unloadModel();
      }

      const params = GenerationParams(
        prompt: 'This should fail',
        maxTokens: 10,
      );

      expect(
        () => llama.generate(params),
        throwsA(isA<StateError>()),
        reason: 'Should throw StateError when model not loaded',
      );
    }, skip: testModelPath.isEmpty);
  });

  group('OllamaModelDownloader Tests', () {
    test('lists available model variants', () {
      final variants = OllamaModelDownloader.getAvailableVariants();

      expect(variants, isNotEmpty);
      expect(variants, contains('q2_k'));
      expect(variants, contains('q4_k_s'));
      expect(variants, contains('latest'));

      print('[Test] Available variants: ${variants.join(", ")}');
    });

    test('gets model info for each variant', () {
      final variants = OllamaModelDownloader.getAvailableVariants();

      for (final variant in variants) {
        final info = OllamaModelDownloader.getModelInfo(variant);

        expect(info, isNotNull);
        expect(info['variant'], variant);
        expect(info['fileName'], isNotEmpty);
        expect(info['size'], isNotEmpty);

        print('[Test] $variant: ${info['size']}');
      }
    });

    test('validates GGUF file format check', () async {
      // Test with non-existent file
      final isValid = await OllamaModelDownloader.isValidGGUFFile(
        '/nonexistent/model.gguf',
      );
      expect(isValid, false);
    });
  });

  group('Model Loading Configuration Tests', () {
    testWidgets('handles invalid model path', (WidgetTester tester) async {
      final llama = FlutterLlama.instance;

      const config = LlamaConfig(
        modelPath: '/invalid/path/model.gguf',
        nThreads: 2,
        contextSize: 512,
      );

      final result = await llama.loadModel(config);

      expect(result, false, reason: 'Should fail to load invalid model path');
      expect(llama.isModelLoaded, false);
    });

    testWidgets('handles different thread configurations', (
      WidgetTester tester,
    ) async {
      final llama = FlutterLlama.instance;

      final threadCounts = [1, 2, 4, 8];

      for (final threads in threadCounts) {
        final config = LlamaConfig(
          modelPath: '/test/model.gguf',
          nThreads: threads,
        );

        expect(config.nThreads, threads);
        print('[Test] Config with $threads threads created');
      }
    });

    testWidgets('handles different context sizes', (WidgetTester tester) async {
      final contextSizes = [512, 1024, 2048, 4096];

      for (final size in contextSizes) {
        final config = LlamaConfig(
          modelPath: '/test/model.gguf',
          contextSize: size,
        );

        expect(config.contextSize, size);
        print('[Test] Config with context size $size created');
      }
    });
  });
}





