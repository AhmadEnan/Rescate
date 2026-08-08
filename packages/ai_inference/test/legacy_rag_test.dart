import 'package:ai_inference/ai_inference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegacyRag.buildPrompt', () {
    test(
      'ordinary factual question is preserved and answered by the model',
      () {
        const question = 'Normal blood pressure range?';

        final prompt = LegacyRag.buildPrompt(
          question: question,
          chunks: const <Map<String, dynamic>>[],
        );

        expect(prompt, contains('QUESTION: $question'));
        expect(prompt, contains('MEDICAL REFERENCE:'));
        expect(prompt, contains('NO_RELEVANT_CONTEXT'));
        expect(prompt, contains('<|think|>'));
        expect(prompt, contains('<|channel>thought'));
        expect(prompt, contains('<channel|>'));

        // Regression guard: prompt construction supplies instructions and
        // retrieved context only. It must not inject a canned medical answer.
        expect(prompt, isNot(contains('120/80')));
        expect(prompt, isNot(contains('90/60')));
      },
    );

    test('English safety instructions remain direct and concise', () {
      final prompt = LegacyRag.buildPrompt(
        question: 'Someone is choking',
        chunks: const <Map<String, dynamic>>[
          <String, dynamic>{
            'text':
                'Choking reference text that the model should use to form its own answer.',
          },
        ],
      );

      expect(
        prompt,
        contains('Answer every clear factual or general question directly'),
      );
      expect(prompt, contains('give short numbered actions immediately'));
      expect(prompt, contains('Never reply with only a question'));
      expect(prompt, contains('when to call emergency services'));
      expect(prompt, contains('Someone is choking'));
      expect(prompt.length, lessThan(1100));
    });

    test('Arabic prompt preserves the question and safety instructions', () {
      const question = 'شخص لا يتنفس، ماذا أفعل؟';

      final prompt = LegacyRag.buildPrompt(
        question: question,
        chunks: const <Map<String, dynamic>>[],
      );

      expect(prompt, contains('السؤال: $question'));
      expect(prompt, contains('أجب مباشرة عن كل سؤال عام أو واضح'));
      expect(prompt, contains('أعطِ خطوات قصيرة ومرتبة فوراً'));
      expect(prompt, contains('لا ترد بسؤال فقط'));
      expect(prompt, contains('متى يجب الاتصال بالطوارئ'));
      expect(prompt.length, lessThan(1100));
    });

    test('retrieved context is bounded before model inference', () {
      final longText = List<String>.filled(80, 'reference').join(' ');

      final prompt = LegacyRag.buildPrompt(
        question: 'What should I do?',
        chunks: <Map<String, dynamic>>[
          <String, dynamic>{'text': longText},
          <String, dynamic>{'text': longText},
        ],
      );

      expect(prompt, contains('[1]'));
      expect(prompt, contains('[2]'));
      expect(prompt, isNot(contains(longText)));
      expect(prompt.length, lessThan(1400));
    });

    test('procedural context centers the immediate-action guidance', () {
      final irrelevantPrefix = List<String>.filled(
        60,
        'classification',
      ).join(' ');
      final prompt = LegacyRag.buildPrompt(
        question: 'How to treat a burn?',
        chunks: <Map<String, dynamic>>[
          <String, dynamic>{
            'text':
                '$irrelevantPrefix 4A THERMAL BURNS IMMEDIATE ACTIONS: '
                'STOP THE BURNING. COOL with running water. COVER loosely.',
          },
        ],
      );

      expect(prompt, contains('IMMEDIATE ACTIONS'));
      expect(prompt, contains('COOL with running water'));
      expect(prompt, isNot(contains(irrelevantPrefix)));
    });

    test('tool declarations are included only when explicitly supplied', () {
      final ordinaryPrompt = LegacyRag.buildPrompt(
        question: 'What is a normal pulse?',
        chunks: const <Map<String, dynamic>>[],
      );
      final toolPrompt = LegacyRag.buildPrompt(
        question: 'Open the CPR tutorial',
        chunks: const <Map<String, dynamic>>[],
        toolDeclarations: 'TOOLS: open_cpr_tutorial',
      );

      expect(ordinaryPrompt, isNot(contains('TOOLS:')));
      expect(toolPrompt, contains('TOOLS: open_cpr_tutorial'));
    });

    test('full reasoning remains opt-in', () {
      final prompt = LegacyRag.buildPrompt(
        question: 'How should I treat a burn?',
        chunks: const <Map<String, dynamic>>[],
        enableThinking: true,
      );

      expect(prompt, contains('<|think|>'));
      expect(prompt, isNot(contains('<|channel>thought')));
      expect(prompt, endsWith('<|turn>model\n'));
    });
  });
}
