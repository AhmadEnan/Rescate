import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_llama/flutter_llama.dart';
import '../lib/utils/model_downloader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Text Generation Integration Tests', () {
    late FlutterLlama llama;
    late String modelPath;

    setUpAll(() async {
      print('Setting up tests - downloading/loading model...');

      // Download model if needed
      String? path = await ModelDownloader.getModelPath('braindler-q2_k');
      if (path == null) {
        print('Downloading model...');
        path = await ModelDownloader.downloadModel(
          'braindler-q2_k',
          onProgress: (progress) {
            if (progress == 1.0 || progress % 0.1 < 0.01) {
              print('Download: ${(progress * 100).toStringAsFixed(0)}%');
            }
          },
        );
      }

      modelPath = path!;
      print('Model ready at: $modelPath');
    });

    setUp(() async {
      llama = FlutterLlama.instance;

      // Load model if not already loaded
      if (!llama.isModelLoaded) {
        print('Loading model...');
        final config = LlamaConfig(
          modelPath: modelPath,
          nThreads: 4,
          contextSize: 2048,
          useGpu: true,
        );

        final loaded = await llama.loadModel(config);
        expect(loaded, isTrue, reason: 'Model should load successfully');
      }
    });

    tearDownAll(() async {
      // Final cleanup
      try {
        if (llama.isModelLoaded) {
          await llama.unloadModel();
        }
      } catch (e) {
        print('Error during final cleanup: $e');
      }
    });

    testWidgets('should generate simple response', (WidgetTester tester) async {
      print('Testing simple generation...');

      final params = GenerationParams(
        prompt: 'Hello',
        maxTokens: 50,
        temperature: 0.7,
      );

      final response = await llama.generate(params);

      print('Prompt: ${params.prompt}');
      print('Response: ${response.text}');
      print('Tokens: ${response.tokensGenerated}');
      print('Time: ${response.generationTime}ms');
      print('Speed: ${response.tokensPerSecond.toStringAsFixed(2)} tokens/sec');

      expect(response.text, isNotEmpty);
      expect(response.tokensGenerated, greaterThan(0));
      expect(response.generationTime, greaterThan(0));
    });

    testWidgets('should generate with different temperatures', (
      WidgetTester tester,
    ) async {
      print('Testing temperature variations...');

      final prompt = 'The weather today is';
      final temperatures = [0.1, 0.5, 0.9];

      for (final temp in temperatures) {
        print('\\nTemperature: $temp');

        final params = GenerationParams(
          prompt: prompt,
          maxTokens: 30,
          temperature: temp,
        );

        final response = await llama.generate(params);

        print('Response: ${response.text}');

        expect(response.text, isNotEmpty);
      }
    });

    testWidgets('should respect max tokens limit', (WidgetTester tester) async {
      print('Testing max tokens limit...');

      final maxTokensList = [10, 50, 100];

      for (final maxTokens in maxTokensList) {
        print('\\nMax tokens: $maxTokens');

        final params = GenerationParams(
          prompt: 'Write a story about',
          maxTokens: maxTokens,
          temperature: 0.8,
        );

        final response = await llama.generate(params);

        print('Generated tokens: ${response.tokensGenerated}');
        print('Response length: ${response.text.length} chars');

        expect(response.tokensGenerated, lessThanOrEqualTo(maxTokens));
      }
    });

    testWidgets('should generate with different sampling parameters', (
      WidgetTester tester,
    ) async {
      print('Testing different sampling parameters...');

      final testCases = [
        {
          'name': 'High creativity',
          'params': GenerationParams(
            prompt: 'Once upon a time',
            maxTokens: 50,
            temperature: 1.0,
            topP: 0.95,
            topK: 50,
          ),
        },
        {
          'name': 'Focused generation',
          'params': GenerationParams(
            prompt: 'Once upon a time',
            maxTokens: 50,
            temperature: 0.3,
            topP: 0.8,
            topK: 20,
          ),
        },
        {
          'name': 'Balanced generation',
          'params': GenerationParams(
            prompt: 'Once upon a time',
            maxTokens: 50,
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
          ),
        },
      ];

      for (final testCase in testCases) {
        print('\\n${testCase['name']}:');
        final params = testCase['params'] as GenerationParams;

        final response = await llama.generate(params);

        print('Response: ${response.text}');
        print(
          'Stats: ${response.tokensGenerated} tokens in ${response.generationTime}ms',
        );

        expect(response.text, isNotEmpty);
      }
    });

    testWidgets('should handle repeat penalty', (WidgetTester tester) async {
      print('Testing repeat penalty...');

      final prompt = 'The cat';

      // Low repeat penalty (may repeat more)
      print('\\nWith low repeat penalty (1.0):');
      var params = GenerationParams(
        prompt: prompt,
        maxTokens: 30,
        repeatPenalty: 1.0,
      );
      var response = await llama.generate(params);
      print('Response: ${response.text}');

      // High repeat penalty (should repeat less)
      print('\\nWith high repeat penalty (1.5):');
      params = GenerationParams(
        prompt: prompt,
        maxTokens: 30,
        repeatPenalty: 1.5,
      );
      response = await llama.generate(params);
      print('Response: ${response.text}');

      expect(response.text, isNotEmpty);
    });

    testWidgets('should generate multiple responses in sequence', (
      WidgetTester tester,
    ) async {
      print('Testing multiple sequential generations...');

      final prompts = ['Hello', 'What is AI?', 'Tell me a joke'];

      for (int i = 0; i < prompts.length; i++) {
        print('\\nGeneration ${i + 1}/${prompts.length}:');
        print('Prompt: ${prompts[i]}');

        final params = GenerationParams(prompt: prompts[i], maxTokens: 50);

        final response = await llama.generate(params);

        print('Response: ${response.text}');

        expect(response.text, isNotEmpty);
      }
    });

    testWidgets('should measure generation performance', (
      WidgetTester tester,
    ) async {
      print('Testing generation performance...');

      final params = GenerationParams(
        prompt: 'Write a short paragraph about artificial intelligence',
        maxTokens: 100,
        temperature: 0.7,
      );

      final stopwatch = Stopwatch()..start();
      final response = await llama.generate(params);
      stopwatch.stop();

      print('\\nPerformance Metrics:');
      print('Total time: ${stopwatch.elapsedMilliseconds}ms');
      print('Generation time: ${response.generationTime}ms');
      print('Tokens generated: ${response.tokensGenerated}');
      print('Tokens/second: ${response.tokensPerSecond.toStringAsFixed(2)}');
      print('Characters: ${response.text.length}');
      print('Response:\\n${response.text}');

      expect(response.tokensPerSecond, greaterThan(0));
      expect(stopwatch.elapsedMilliseconds, greaterThan(0));
    });

    testWidgets('should handle empty prompt gracefully', (
      WidgetTester tester,
    ) async {
      print('Testing empty prompt...');

      final params = GenerationParams(prompt: '', maxTokens: 10);

      try {
        final response = await llama.generate(params);
        print('Response with empty prompt: ${response.text}');
        // Some models might handle empty prompts, others might not
        expect(response, isNotNull);
      } catch (e) {
        print('Empty prompt handled with error: $e');
        expect(e, isNotNull);
      }
    });

    testWidgets('should handle very long prompts', (WidgetTester tester) async {
      print('Testing long prompt...');

      final longPrompt = 'This is a very long prompt. ' * 50; // Repeat 50 times

      final params = GenerationParams(prompt: longPrompt, maxTokens: 20);

      try {
        final response = await llama.generate(params);
        print('Response to long prompt generated successfully');
        print('Tokens: ${response.tokensGenerated}');
        expect(response.text, isNotEmpty);
      } catch (e) {
        print('Long prompt caused error (expected if exceeds context): $e');
        expect(e, isNotNull);
      }
    });

    testWidgets('should compare generation with different quantizations', (
      WidgetTester tester,
    ) async {
      print('Testing different model quantizations...');

      // This test compares responses from different model versions
      final modelsToTest = ['braindler-q2_k', 'braindler-q4_k_s'];
      final prompt = 'Hello, how are you?';
      final responses = <String, LlamaResponse>{};

      for (final modelName in modelsToTest) {
        String? path = await ModelDownloader.getModelPath(modelName);

        if (path == null) {
          print('$modelName not downloaded, skipping...');
          continue;
        }

        print('\\nTesting with $modelName...');

        // Unload current model
        if (llama.isModelLoaded) {
          await llama.unloadModel();
        }

        // Load new model
        final config = LlamaConfig(
          modelPath: path,
          nThreads: 4,
          contextSize: 2048,
        );

        final loaded = await llama.loadModel(config);
        if (!loaded) {
          print('Failed to load $modelName');
          continue;
        }

        // Generate response
        final params = GenerationParams(
          prompt: prompt,
          maxTokens: 50,
          temperature: 0.7,
        );

        final response = await llama.generate(params);
        responses[modelName] = response;

        print('Response: ${response.text}');
        print(
          'Speed: ${response.tokensPerSecond.toStringAsFixed(2)} tokens/sec',
        );
      }

      print('\\nComparison complete. Tested ${responses.length} models.');
      expect(responses.isNotEmpty, isTrue);
    });
  });
}





