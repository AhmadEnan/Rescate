import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterLlama Comprehensive Tests', () {
    const MethodChannel channel = MethodChannel('flutter_llama');
    late FlutterLlama llama;

    setUp(() {
      llama = FlutterLlama.instance;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('Singleton Pattern', () {
      test('should return same instance', () {
        final instance1 = FlutterLlama.instance;
        final instance2 = FlutterLlama.instance;
        expect(identical(instance1, instance2), isTrue);
      });

      test('should maintain state across instances', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            }
            return null;
          },
        );

        final instance1 = FlutterLlama.instance;
        await instance1.loadModel(
          LlamaConfig(modelPath: '/path/to/model.gguf'),
        );

        final instance2 = FlutterLlama.instance;
        expect(instance2.isModelLoaded, isTrue);
        expect(instance2.modelPath, '/path/to/model.gguf');
      });
    });

    group('Model Loading', () {
      test('should successfully load model with default config', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              expect(methodCall.arguments, isA<Map>());
              final args = methodCall.arguments as Map;
              expect(args['modelPath'], '/test/model.gguf');
              expect(args['nThreads'], 4);
              expect(args['contextSize'], 2048);
              return true;
            }
            return null;
          },
        );

        final result = await llama.loadModel(
          LlamaConfig(modelPath: '/test/model.gguf'),
        );

        expect(result, isTrue);
        expect(llama.isModelLoaded, isTrue);
        expect(llama.isInitialized, isTrue);
        expect(llama.modelPath, '/test/model.gguf');
      });

      test('should load model with custom config', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              final args = methodCall.arguments as Map;
              expect(args['nThreads'], 8);
              expect(args['contextSize'], 4096);
              expect(args['nGpuLayers'], 32);
              expect(args['useGpu'], true);
              return true;
            }
            return null;
          },
        );

        final result = await llama.loadModel(
          LlamaConfig(
            modelPath: '/test/model.gguf',
            nThreads: 8,
            contextSize: 4096,
            nGpuLayers: 32,
            useGpu: true,
          ),
        );

        expect(result, isTrue);
      });

      test('should handle loading failure', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return false;
            }
            return null;
          },
        );

        final result = await llama.loadModel(
          LlamaConfig(modelPath: '/invalid/model.gguf'),
        );

        expect(result, isFalse);
        expect(llama.isModelLoaded, isFalse);
        expect(llama.isInitialized, isFalse);
      });

      test('should handle loading exception', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              throw PlatformException(
                code: 'LOAD_ERROR',
                message: 'Failed to load model',
              );
            }
            return null;
          },
        );

        final result = await llama.loadModel(
          LlamaConfig(modelPath: '/error/model.gguf'),
        );

        expect(result, isFalse);
        expect(llama.isModelLoaded, isFalse);
      });
    });

    group('Text Generation', () {
      setUp(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            }
            return null;
          },
        );
        await llama.loadModel(LlamaConfig(modelPath: '/test/model.gguf'));
      });

      test('should generate text with default params', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            } else if (methodCall.method == 'generate') {
              final args = methodCall.arguments as Map;
              expect(args['prompt'], 'Hello');
              expect(args['temperature'], 0.8);
              expect(args['maxTokens'], 512);

              return {
                'text': 'Hello! How can I help you?',
                'tokensGenerated': 6,
                'generationTimeMs': 150,
              };
            }
            return null;
          },
        );

        final response = await llama.generate(
          GenerationParams(prompt: 'Hello'),
        );

        expect(response.text, 'Hello! How can I help you?');
        expect(response.tokensGenerated, 6);
        expect(response.generationTimeMs, 150);
        expect(response.tokensPerSecond, greaterThan(0));
      });

      test('should generate with custom params', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            } else if (methodCall.method == 'generate') {
              final args = methodCall.arguments as Map;
              expect(args['temperature'], 0.7);
              expect(args['topP'], 0.9);
              expect(args['topK'], 50);
              expect(args['maxTokens'], 256);
              expect(args['repeatPenalty'], 1.2);

              return {
                'text': 'Generated response',
                'tokensGenerated': 10,
                'generationTimeMs': 200,
              };
            }
            return null;
          },
        );

        final response = await llama.generate(
          GenerationParams(
            prompt: 'Test prompt',
            temperature: 0.7,
            topP: 0.9,
            topK: 50,
            maxTokens: 256,
            repeatPenalty: 1.2,
          ),
        );

        expect(response.text, 'Generated response');
      });

      test('should throw error when model not loaded', () async {
        final newLlama = FlutterLlama.instance;
        // Reset state
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'unloadModel') {
              return null;
            }
            return null;
          },
        );

        await newLlama.unloadModel();

        expect(
          () => newLlama.generate(GenerationParams(prompt: 'Test')),
          throwsA(isA<StateError>()),
        );
      });

      test('should handle generation error', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            } else if (methodCall.method == 'generate') {
              throw PlatformException(
                code: 'GENERATION_ERROR',
                message: 'Failed to generate',
              );
            }
            return null;
          },
        );

        expect(
          () => llama.generate(GenerationParams(prompt: 'Test')),
          throwsA(isA<PlatformException>()),
        );
      });
    });

    group('Model Unloading', () {
      test('should successfully unload model', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            } else if (methodCall.method == 'unloadModel') {
              return null;
            }
            return null;
          },
        );

        await llama.loadModel(LlamaConfig(modelPath: '/test/model.gguf'));
        expect(llama.isModelLoaded, isTrue);

        await llama.unloadModel();
        expect(llama.isModelLoaded, isFalse);
        expect(llama.modelPath, isNull);
      });
    });

    group('Model Info', () {
      test('should return model info when loaded', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'loadModel') {
              return true;
            } else if (methodCall.method == 'getModelInfo') {
              return {
                'modelPath': '/test/model.gguf',
                'contextSize': 2048,
                'vocabSize': 32000,
              };
            }
            return null;
          },
        );

        await llama.loadModel(LlamaConfig(modelPath: '/test/model.gguf'));
        final info = await llama.getModelInfo();

        expect(info, isNotNull);
        expect(info!['modelPath'], '/test/model.gguf');
        expect(info['contextSize'], 2048);
        expect(info['vocabSize'], 32000);
      });

      test('should return null when model not loaded', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'unloadModel') {
              return null;
            }
            return null;
          },
        );

        await llama.unloadModel();
        final info = await llama.getModelInfo();
        expect(info, isNull);
      });
    });

    group('Stop Generation', () {
      test('should call stopGeneration method', () async {
        bool stopCalled = false;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'stopGeneration') {
              stopCalled = true;
              return null;
            }
            return null;
          },
        );

        await llama.stopGeneration();
        expect(stopCalled, isTrue);
      });
    });
  });

  group('LlamaConfig Tests', () {
    test('should create config with default values', () {
      final config = LlamaConfig(modelPath: '/test/model.gguf');

      expect(config.modelPath, '/test/model.gguf');
      expect(config.nThreads, 4);
      expect(config.nGpuLayers, 0);
      expect(config.contextSize, 2048);
      expect(config.batchSize, 512);
      expect(config.useGpu, true);
      expect(config.verbose, false);
    });

    test('should create config with custom values', () {
      final config = LlamaConfig(
        modelPath: '/custom/model.gguf',
        nThreads: 8,
        nGpuLayers: 32,
        contextSize: 4096,
        batchSize: 1024,
        useGpu: false,
        verbose: true,
      );

      expect(config.nThreads, 8);
      expect(config.nGpuLayers, 32);
      expect(config.contextSize, 4096);
      expect(config.batchSize, 1024);
      expect(config.useGpu, false);
      expect(config.verbose, true);
    });

    test('should convert to map correctly', () {
      final config = LlamaConfig(
        modelPath: '/test/model.gguf',
        nThreads: 6,
      );

      final map = config.toMap();

      expect(map['modelPath'], '/test/model.gguf');
      expect(map['nThreads'], 6);
      expect(map['contextSize'], 2048);
    });
  });

  group('GenerationParams Tests', () {
    test('should create params with default values', () {
      final params = GenerationParams(prompt: 'Test');

      expect(params.prompt, 'Test');
      expect(params.temperature, 0.8);
      expect(params.topP, 0.95);
      expect(params.topK, 40);
      expect(params.maxTokens, 512);
      expect(params.repeatPenalty, 1.1);
      expect(params.stopSequences, isEmpty);
    });

    test('should create params with custom values', () {
      final params = GenerationParams(
        prompt: 'Custom prompt',
        temperature: 0.7,
        topP: 0.9,
        topK: 50,
        maxTokens: 256,
        repeatPenalty: 1.2,
        stopSequences: ['\\n', 'END'],
      );

      expect(params.temperature, 0.7);
      expect(params.topP, 0.9);
      expect(params.topK, 50);
      expect(params.maxTokens, 256);
      expect(params.repeatPenalty, 1.2);
      expect(params.stopSequences, ['\\n', 'END']);
    });

    test('should convert to map correctly', () {
      final params = GenerationParams(
        prompt: 'Test prompt',
        maxTokens: 100,
      );

      final map = params.toMap();

      expect(map['prompt'], 'Test prompt');
      expect(map['maxTokens'], 100);
      expect(map['temperature'], 0.8);
    });
  });
}
