import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() {
  group('GenerationParams', () {
    test('creates params with required prompt only', () {
      const params = GenerationParams(
        prompt: 'Hello, world!',
      );

      expect(params.prompt, 'Hello, world!');
      expect(params.temperature, 0.8);
      expect(params.topP, 0.95);
      expect(params.topK, 40);
      expect(params.maxTokens, 512);
      expect(params.repeatPenalty, 1.1);
      expect(params.stopSequences, isEmpty);
    });

    test('creates params with custom values', () {
      const params = GenerationParams(
        prompt: 'Custom prompt',
        temperature: 0.5,
        topP: 0.9,
        topK: 50,
        maxTokens: 1024,
        repeatPenalty: 1.2,
        stopSequences: ['\n', 'END'],
      );

      expect(params.prompt, 'Custom prompt');
      expect(params.temperature, 0.5);
      expect(params.topP, 0.9);
      expect(params.topK, 50);
      expect(params.maxTokens, 1024);
      expect(params.repeatPenalty, 1.2);
      expect(params.stopSequences, ['\n', 'END']);
    });

    test('toMap converts params to map correctly', () {
      const params = GenerationParams(
        prompt: 'Test prompt',
        temperature: 0.7,
        topP: 0.85,
        topK: 30,
        maxTokens: 256,
        repeatPenalty: 1.15,
        stopSequences: ['STOP', 'END'],
      );

      final map = params.toMap();

      expect(map['prompt'], 'Test prompt');
      expect(map['temperature'], 0.7);
      expect(map['topP'], 0.85);
      expect(map['topK'], 30);
      expect(map['maxTokens'], 256);
      expect(map['repeatPenalty'], 1.15);
      expect(map['stopSequences'], ['STOP', 'END']);
    });

    test('toString returns formatted string', () {
      const params = GenerationParams(
        prompt: 'A very long prompt for testing',
        temperature: 0.8,
        maxTokens: 512,
      );

      final str = params.toString();

      expect(str, contains('GenerationParams'));
      expect(str, contains('temperature: 0.8'));
      expect(str, contains('maxTokens: 512'));
      expect(str, contains('prompt length: 30'));
    });

    test('handles temperature extremes', () {
      const lowTemp = GenerationParams(
        prompt: 'Test',
        temperature: 0.0,
      );

      const highTemp = GenerationParams(
        prompt: 'Test',
        temperature: 2.0,
      );

      expect(lowTemp.temperature, 0.0);
      expect(highTemp.temperature, 2.0);
    });

    test('handles topP values', () {
      const minTopP = GenerationParams(
        prompt: 'Test',
        topP: 0.0,
      );

      const maxTopP = GenerationParams(
        prompt: 'Test',
        topP: 1.0,
      );

      expect(minTopP.topP, 0.0);
      expect(maxTopP.topP, 1.0);
    });

    test('handles empty and multiple stop sequences', () {
      const noStops = GenerationParams(
        prompt: 'Test',
        stopSequences: [],
      );

      const multipleStops = GenerationParams(
        prompt: 'Test',
        stopSequences: ['\n', '###', 'STOP', 'END'],
      );

      expect(noStops.stopSequences, isEmpty);
      expect(multipleStops.stopSequences.length, 4);
    });

    test('handles very long prompts', () {
      final longPrompt = 'A' * 10000;
      final params = GenerationParams(
        prompt: longPrompt,
      );

      expect(params.prompt.length, 10000);
      expect(params.toString(), contains('prompt length: 10000'));
    });

    test('params with same values produce same map', () {
      const params1 = GenerationParams(
        prompt: 'Same prompt',
        temperature: 0.8,
      );

      const params2 = GenerationParams(
        prompt: 'Same prompt',
        temperature: 0.8,
      );

      expect(params1.toMap().toString(), params2.toMap().toString());
    });
  });
}
