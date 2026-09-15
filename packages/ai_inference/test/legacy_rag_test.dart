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

      // The legacy (embedder-less) path and the v3 path now share one system
      // prompt, so these assert the unified text's invariants rather than the
      // old legacy-only wording that used to drift out of sync with v3 - a
      // drift that had left this path without the prescription-dosing guard.
      expect(prompt, contains("Match the user's register"));
      expect(prompt, contains('not emergency instructions'));
      expect(prompt, contains('short numbered steps'));
      expect(prompt, contains('then what to watch for'));
      expect(
        prompt,
        contains('Never recommend or dose prescription medicines'),
        reason: 'the dosing guard must exist on the legacy path too',
      );
      expect(prompt, contains('Someone is choking'));
      // The enumerated scaffold is what the model used to regurgitate.
      expect(prompt, isNot(contains('SAFETY FIRST')));
      expect(prompt, isNot(contains('Order of thinking')));
      // ~1,040 chars today, 790 of them the system prompt. The bound is a
      // regression guard against the 2,275-char warzone prompt returning.
      expect(prompt.length, lessThan(1200));
    });

    test('Arabic prompt preserves the question and safety instructions', () {
      const question = 'شخص لا يتنفس، ماذا أفعل؟';

      final prompt = LegacyRag.buildPrompt(
        question: question,
        chunks: const <Map<String, dynamic>>[],
      );

      expect(prompt, contains('السؤال: $question'));
      expect(prompt, contains('طابق أسلوب السؤال'));
      expect(prompt, contains('وليس تعليمات طوارئ'));
      expect(prompt, contains('خطوات قصيرة مرقمة'));
      expect(prompt, contains('ما يجب مراقبته'));
      expect(
        prompt,
        contains('لا تصف جرعات أدوية بوصفة'),
        reason: 'the dosing guard must exist on the Arabic path too',
      );
      expect(prompt.length, lessThan(1200));
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
