import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('flutter_llama');

  final List<MethodCall> methodCallLog = <MethodCall>[];
  final FlutterLlama llama = FlutterLlama.instance;

  setUp(() {
    methodCallLog.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCallLog.add(methodCall);

      switch (methodCall.method) {
        case 'loadModel':
          return true;
        case 'generate':
          return {
            'text': 'Generated response',
            'tokensGenerated': 10,
            'generationTimeMs': 100,
          };
        case 'getModelInfo':
          return {
            'modelName': 'test-model',
            'contextSize': 2048,
          };
        case 'unloadModel':
          return null;
        case 'stopGeneration':
          return null;
        case 'generateStream':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FlutterLlama Singleton', () {
    test('instance returns same object', () {
      final instance1 = FlutterLlama.instance;
      final instance2 = FlutterLlama.instance;
      expect(identical(instance1, instance2), true);
    });

    test('initial state is not loaded and not initialized', () {
      expect(llama.isModelLoaded, false);
      expect(llama.isInitialized, false);
      expect(llama.modelPath, null);
    });
  });

  group('FlutterLlama loadModel', () {
    test('loadModel calls platform method with correct arguments', () async {
      methodCallLog.clear();

      const config = LlamaConfig(
        modelPath: '/path/to/model.gguf',
        nThreads: 4,
        contextSize: 2048,
      );

      final result = await llama.loadModel(config);

      expect(result, true);
      expect(methodCallLog.length, 1);
      expect(methodCallLog[0].method, 'loadModel');
      expect(methodCallLog[0].arguments['modelPath'], '/path/to/model.gguf');
      expect(methodCallLog[0].arguments['nThreads'], 4);
      expect(methodCallLog[0].arguments['contextSize'], 2048);
    });

    test('loadModel updates internal state on success', () async {
      const config = LlamaConfig(modelPath: '/test/model.gguf');

      final result = await llama.loadModel(config);

      expect(result, true);
      expect(llama.isModelLoaded, true);
      expect(llama.isInitialized, true);
      expect(llama.modelPath, '/test/model.gguf');
    });

    test('loadModel handles failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'loadModel') {
          return false;
        }
        return null;
      });

      const config = LlamaConfig(modelPath: '/invalid/model.gguf');
      final result = await llama.loadModel(config);

      expect(result, false);
    });

    test('loadModel handles exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'loadModel') {
          throw PlatformException(code: 'ERROR', message: 'Load failed');
        }
        return null;
      });

      const config = LlamaConfig(modelPath: '/error/model.gguf');
      final result = await llama.loadModel(config);

      expect(result, false);
      expect(llama.isModelLoaded, false);
    });
  });

  group('FlutterLlama generate', () {
    test('generate throws if model not loaded', () async {
      const params = GenerationParams(prompt: 'Test');

      expect(
        () => llama.generate(params),
        throwsA(isA<StateError>()),
      );
    });

    test('generate calls platform method with correct arguments', () async {
      methodCallLog.clear();

      // Load model first
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));
      methodCallLog.clear();

      const params = GenerationParams(
        prompt: 'Hello',
        temperature: 0.7,
        maxTokens: 100,
      );

      await llama.generate(params);

      expect(methodCallLog.length, 1);
      expect(methodCallLog[0].method, 'generate');
      expect(methodCallLog[0].arguments['prompt'], 'Hello');
      expect(methodCallLog[0].arguments['temperature'], 0.7);
      expect(methodCallLog[0].arguments['maxTokens'], 100);
    });

    test('generate returns LlamaResponse', () async {
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));

      const params = GenerationParams(prompt: 'Test prompt');
      final response = await llama.generate(params);

      expect(response, isA<LlamaResponse>());
      expect(response.text, 'Generated response');
      expect(response.tokensGenerated, 10);
      expect(response.generationTimeMs, 100);
    });

    test('generate handles null response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'loadModel') return true;
        if (methodCall.method == 'generate') return null;
        return null;
      });

      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));

      const params = GenerationParams(prompt: 'Test');

      expect(
        () => llama.generate(params),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FlutterLlama unloadModel', () {
    test('unloadModel calls platform method', () async {
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));
      methodCallLog.clear();

      await llama.unloadModel();

      expect(methodCallLog.length, 1);
      expect(methodCallLog[0].method, 'unloadModel');
    });

    test('unloadModel updates internal state', () async {
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));
      await llama.unloadModel();

      expect(llama.isModelLoaded, false);
      expect(llama.modelPath, null);
    });

    test('unloadModel handles exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'loadModel') return true;
        if (methodCall.method == 'unloadModel') {
          throw PlatformException(code: 'ERROR');
        }
        return null;
      });

      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));

      expect(
        () => llama.unloadModel(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('FlutterLlama getModelInfo', () {
    test('getModelInfo returns null when no model loaded', () async {
      // Ensure model is unloaded
      if (llama.isModelLoaded) {
        await llama.unloadModel();
      }

      final info = await llama.getModelInfo();
      expect(info, null);
    });

    test('getModelInfo calls platform method', () async {
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));
      methodCallLog.clear();

      await llama.getModelInfo();

      expect(methodCallLog.length, 1);
      expect(methodCallLog[0].method, 'getModelInfo');
    });

    test('getModelInfo returns model information', () async {
      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));

      final info = await llama.getModelInfo();

      expect(info, isA<Map<String, dynamic>>());
      expect(info?['modelName'], 'test-model');
      expect(info?['contextSize'], 2048);
    });

    test('getModelInfo handles exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'loadModel') return true;
        if (methodCall.method == 'getModelInfo') {
          throw PlatformException(code: 'ERROR');
        }
        return null;
      });

      await llama.loadModel(const LlamaConfig(modelPath: '/test.gguf'));

      final info = await llama.getModelInfo();
      expect(info, null);
    });
  });

  group('FlutterLlama stopGeneration', () {
    test('stopGeneration calls platform method', () async {
      methodCallLog.clear();

      await llama.stopGeneration();

      expect(methodCallLog.length, 1);
      expect(methodCallLog[0].method, 'stopGeneration');
    });

    test('stopGeneration handles exception silently', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'stopGeneration') {
          throw PlatformException(code: 'ERROR');
        }
        return null;
      });

      // Should not throw
      await llama.stopGeneration();
    });
  });
}
