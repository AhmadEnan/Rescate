import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() {
  group('LlamaResponse', () {
    test('creates response with all parameters', () {
      const response = LlamaResponse(
        text: 'Generated text',
        tokensGenerated: 100,
        generationTimeMs: 1000,
      );

      expect(response.text, 'Generated text');
      expect(response.tokensGenerated, 100);
      expect(response.generationTimeMs, 1000);
    });

    test('creates response with defaults', () {
      const response = LlamaResponse(
        text: 'Text only',
      );

      expect(response.text, 'Text only');
      expect(response.tokensGenerated, 0);
      expect(response.generationTimeMs, 0);
    });

    test('calculates tokens per second correctly', () {
      const response = LlamaResponse(
        text: 'Test',
        tokensGenerated: 100,
        generationTimeMs: 1000,
      );

      expect(response.tokensPerSecond, 100.0);
    });

    test('calculates tokens per second for fast generation', () {
      const response = LlamaResponse(
        text: 'Fast',
        tokensGenerated: 500,
        generationTimeMs: 1000,
      );

      expect(response.tokensPerSecond, 500.0);
    });

    test('calculates tokens per second for slow generation', () {
      const response = LlamaResponse(
        text: 'Slow',
        tokensGenerated: 50,
        generationTimeMs: 1000,
      );

      expect(response.tokensPerSecond, 50.0);
    });

    test('handles zero generation time', () {
      const response = LlamaResponse(
        text: 'Zero time',
        tokensGenerated: 100,
        generationTimeMs: 0,
      );

      expect(response.tokensPerSecond, 0.0);
    });

    test('fromMap creates response correctly', () {
      final map = {
        'text': 'Response from map',
        'tokensGenerated': 150,
        'generationTimeMs': 2000,
      };

      final response = LlamaResponse.fromMap(map);

      expect(response.text, 'Response from map');
      expect(response.tokensGenerated, 150);
      expect(response.generationTimeMs, 2000);
      expect(response.tokensPerSecond, 75.0);
    });

    test('fromMap handles missing values with defaults', () {
      final map = {
        'text': 'Partial data',
      };

      final response = LlamaResponse.fromMap(map);

      expect(response.text, 'Partial data');
      expect(response.tokensGenerated, 0);
      expect(response.generationTimeMs, 0);
    });

    test('fromMap handles null values', () {
      final map = {
        'text': null,
        'tokensGenerated': null,
        'generationTimeMs': null,
      };

      final response = LlamaResponse.fromMap(map);

      expect(response.text, '');
      expect(response.tokensGenerated, 0);
      expect(response.generationTimeMs, 0);
    });

    test('fromMap handles empty map', () {
      final map = <String, dynamic>{};

      final response = LlamaResponse.fromMap(map);

      expect(response.text, '');
      expect(response.tokensGenerated, 0);
      expect(response.generationTimeMs, 0);
    });

    test('toString returns formatted string', () {
      const response = LlamaResponse(
        text: 'Test response with some content',
        tokensGenerated: 200,
        generationTimeMs: 2500,
      );

      final str = response.toString();

      expect(str, contains('LlamaResponse'));
      expect(str, contains('31 chars')); // Actual length of the text
      expect(str, contains('tokens: 200'));
      expect(str, contains('time: 2500ms'));
      expect(str, contains('tok/s'));
    });

    test('handles very long text', () {
      final longText = 'A' * 100000;
      final response = LlamaResponse(
        text: longText,
        tokensGenerated: 50000,
        generationTimeMs: 10000,
      );

      expect(response.text.length, 100000);
      expect(response.tokensPerSecond, 5000.0);
      expect(response.toString(), contains('100000 chars'));
    });

    test('handles fractional tokens per second', () {
      const response = LlamaResponse(
        text: 'Fractional speed',
        tokensGenerated: 33,
        generationTimeMs: 1000,
      );

      expect(response.tokensPerSecond, closeTo(33.0, 0.01));
    });

    test('handles very fast generation', () {
      const response = LlamaResponse(
        text: 'Very fast',
        tokensGenerated: 10000,
        generationTimeMs: 100,
      );

      expect(response.tokensPerSecond, 100000.0);
    });

    test('handles very slow generation', () {
      const response = LlamaResponse(
        text: 'Very slow',
        tokensGenerated: 10,
        generationTimeMs: 10000,
      );

      expect(response.tokensPerSecond, 1.0);
    });

    test('empty text response', () {
      const response = LlamaResponse(
        text: '',
        tokensGenerated: 0,
        generationTimeMs: 100,
      );

      expect(response.text, isEmpty);
      expect(response.tokensGenerated, 0);
      expect(response.tokensPerSecond, 0.0);
    });
  });
}
