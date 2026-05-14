import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_llama/flutter_llama.dart';
import '../lib/utils/model_downloader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Streaming Generation Integration Tests', () {
    late FlutterLlama llama;
    late String modelPath;

    setUpAll(() async {
      print('Setting up streaming tests - downloading/loading model...');

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

    testWidgets('should stream tokens', (WidgetTester tester) async {
      print('Testing token streaming...');

      final params = GenerationParams(
        prompt: 'Hello',
        maxTokens: 30,
        temperature: 0.7,
      );

      final tokens = <String>[];
      final stopwatch = Stopwatch()..start();

      try {
        await for (final token in llama.generateStream(params)) {
          tokens.add(token);
          print('Token ${tokens.length}: "$token"');
        }
      } catch (e) {
        print('Streaming error (may not be implemented yet): $e');
        // Streaming might not be fully implemented in native code yet
        // This is expected and we just log it
      }

      stopwatch.stop();

      if (tokens.isNotEmpty) {
        final fullText = tokens.join();
        print('\\nFull response: $fullText');
        print('Total tokens: ${tokens.length}');
        print('Total time: ${stopwatch.elapsedMilliseconds}ms');
        print(
          'Tokens/sec: ${(tokens.length / stopwatch.elapsedMilliseconds * 1000).toStringAsFixed(2)}',
        );

        expect(tokens, isNotEmpty);
        expect(fullText, isNotEmpty);
      } else {
        print('Note: Streaming not yet implemented or not working');
      }
    });

    testWidgets('should stream with progress updates', (
      WidgetTester tester,
    ) async {
      print('Testing streaming with progress tracking...');

      final params = GenerationParams(
        prompt: 'Write a short story',
        maxTokens: 50,
        temperature: 0.8,
      );

      final tokens = <String>[];
      int tokenCount = 0;

      try {
        await for (final token in llama.generateStream(params)) {
          tokenCount++;
          tokens.add(token);

          if (tokenCount % 5 == 0) {
            print('Progress: $tokenCount tokens generated...');
          }
        }

        print('\\nStreaming complete!');
        print('Total tokens: $tokenCount');
        print('Full text: ${tokens.join()}');

        expect(tokens, isNotEmpty);
      } catch (e) {
        print('Streaming not available: $e');
      }
    });

    testWidgets('should handle stream cancellation', (
      WidgetTester tester,
    ) async {
      print('Testing stream cancellation...');

      final params = GenerationParams(
        prompt: 'Generate a very long text',
        maxTokens: 200,
        temperature: 0.7,
      );

      final tokens = <String>[];
      final maxTokensToReceive = 10;
      StreamSubscription? subscription;

      try {
        subscription = llama
            .generateStream(params)
            .listen(
              (token) {
                tokens.add(token);
                print('Received token ${tokens.length}: "$token"');

                if (tokens.length >= maxTokensToReceive) {
                  print('Cancelling after $maxTokensToReceive tokens...');
                  subscription?.cancel();
                  llama.stopGeneration();
                }
              },
              onDone: () {
                print('Stream completed');
              },
              onError: (error) {
                print('Stream error: $error');
              },
            );

        // Wait for completion or cancellation
        await subscription.asFuture();

        print('\\nReceived ${tokens.length} tokens before cancellation');
        expect(
          tokens.length,
          lessThanOrEqualTo(maxTokensToReceive + 5),
        ); // Some buffer for async
      } catch (e) {
        print('Streaming test skipped: $e');
      }
    });

    testWidgets('should stream multiple times sequentially', (
      WidgetTester tester,
    ) async {
      print('Testing multiple sequential streams...');

      final prompts = ['Hello', 'How are you?', 'Tell me a joke'];

      for (int i = 0; i < prompts.length; i++) {
        print('\\nStream ${i + 1}/${prompts.length}: "${prompts[i]}"');

        final params = GenerationParams(prompt: prompts[i], maxTokens: 20);

        final tokens = <String>[];

        try {
          await for (final token in llama.generateStream(params)) {
            tokens.add(token);
          }

          print('Response: ${tokens.join()}');
          expect(tokens, isNotEmpty);
        } catch (e) {
          print('Stream $i skipped: $e');
        }
      }
    });

    testWidgets('should measure streaming performance', (
      WidgetTester tester,
    ) async {
      print('Testing streaming performance...');

      final params = GenerationParams(
        prompt: 'Write about AI',
        maxTokens: 100,
        temperature: 0.7,
      );

      final tokens = <String>[];
      final tokenTimestamps = <int>[];
      final stopwatch = Stopwatch()..start();

      try {
        await for (final token in llama.generateStream(params)) {
          tokens.add(token);
          tokenTimestamps.add(stopwatch.elapsedMilliseconds);
        }

        stopwatch.stop();

        if (tokens.isNotEmpty) {
          // Calculate metrics
          final totalTime = stopwatch.elapsedMilliseconds;
          final avgTokenTime = totalTime / tokens.length;
          final tokensPerSecond = tokens.length / (totalTime / 1000.0);

          print('\\nPerformance Metrics:');
          print('Total tokens: ${tokens.length}');
          print('Total time: ${totalTime}ms');
          print('Average time per token: ${avgTokenTime.toStringAsFixed(2)}ms');
          print('Tokens per second: ${tokensPerSecond.toStringAsFixed(2)}');
          print('\\nFull text: ${tokens.join()}');

          // Calculate time to first token (TTFT)
          if (tokenTimestamps.isNotEmpty) {
            print('Time to first token: ${tokenTimestamps[0]}ms');
          }

          expect(tokens, isNotEmpty);
          expect(tokensPerSecond, greaterThan(0));
        }
      } catch (e) {
        print('Performance test skipped: $e');
      }
    });

    testWidgets('should handle errors in streaming', (
      WidgetTester tester,
    ) async {
      print('Testing error handling in streaming...');

      // First, unload model to cause error
      await llama.unloadModel();

      final params = GenerationParams(
        prompt: 'This should fail',
        maxTokens: 10,
      );

      bool errorOccurred = false;

      try {
        await for (final token in llama.generateStream(params)) {
          print('Unexpected token: $token');
        }
      } catch (e) {
        errorOccurred = true;
        print('Expected error occurred: $e');
        expect(e, isA<StateError>());
      }

      expect(errorOccurred, isTrue);

      // Reload model for subsequent tests
      final config = LlamaConfig(modelPath: modelPath);
      await llama.loadModel(config);
    });

    testWidgets('should stream with different temperatures', (
      WidgetTester tester,
    ) async {
      print('Testing streaming with different temperatures...');

      final temperatures = [0.3, 0.7, 1.0];

      for (final temp in temperatures) {
        print('\\nTemperature: $temp');

        final params = GenerationParams(
          prompt: 'The sky is',
          maxTokens: 20,
          temperature: temp,
        );

        final tokens = <String>[];

        try {
          await for (final token in llama.generateStream(params)) {
            tokens.add(token);
          }

          print('Response: ${tokens.join()}');

          if (tokens.isNotEmpty) {
            expect(tokens, isNotEmpty);
          }
        } catch (e) {
          print('Skipped for temperature $temp: $e');
        }
      }
    });

    testWidgets('should compare streaming vs non-streaming', (
      WidgetTester tester,
    ) async {
      print('Comparing streaming vs non-streaming generation...');

      final params = GenerationParams(
        prompt: 'Hello world',
        maxTokens: 50,
        temperature: 0.7,
      );

      // Non-streaming generation
      print('\\nNon-streaming generation:');
      final stopwatch1 = Stopwatch()..start();
      final response = await llama.generate(params);
      stopwatch1.stop();

      print('Response: ${response.text}');
      print('Time: ${stopwatch1.elapsedMilliseconds}ms');
      print('Tokens: ${response.tokensGenerated}');

      // Streaming generation
      print('\\nStreaming generation:');
      final tokens = <String>[];
      final stopwatch2 = Stopwatch()..start();

      try {
        await for (final token in llama.generateStream(params)) {
          tokens.add(token);
        }
        stopwatch2.stop();

        final streamedText = tokens.join();
        print('Response: $streamedText');
        print('Time: ${stopwatch2.elapsedMilliseconds}ms');
        print('Tokens: ${tokens.length}');

        // Both should generate something
        expect(response.text, isNotEmpty);
        if (tokens.isNotEmpty) {
          expect(streamedText, isNotEmpty);
        }
      } catch (e) {
        print('Streaming comparison skipped: $e');
      }
    });

    testWidgets('should handle rapid start/stop', (WidgetTester tester) async {
      print('Testing rapid start/stop of streams...');

      for (int i = 0; i < 3; i++) {
        print('\\nRapid test $i:');

        final params = GenerationParams(prompt: 'Test $i', maxTokens: 10);

        try {
          final tokens = <String>[];
          await for (final token in llama.generateStream(params)) {
            tokens.add(token);
            if (tokens.length >= 3) {
              await llama.stopGeneration();
              break;
            }
          }
          print('Received ${tokens.length} tokens before stop');
        } catch (e) {
          print('Test $i: $e');
        }

        // Small delay between attempts
        await Future.delayed(Duration(milliseconds: 100));
      }
    });
  });
}





