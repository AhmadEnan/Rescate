import 'package:ai_inference/ai_inference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolCallParser.parse', () {
    test('extracts a single string-only call', () {
      final calls = ToolCallParser.parse(
        '<|tool_call>call:get_biometric{metric:<|"|>heart_rate<|"|>}<tool_call|>',
      );
      expect(calls, hasLength(1));
      expect(calls.first.name, 'get_biometric');
      expect(calls.first.args, {'metric': 'heart_rate'});
    });

    test('extracts mixed string + number + bool args', () {
      final calls = ToolCallParser.parse(
        '<|tool_call>call:foo{a:<|"|>hi<|"|>,b:42,c:true,d:3.14}<tool_call|>',
      );
      expect(calls, hasLength(1));
      expect(calls.first.args, {
        'a': 'hi',
        'b': 42,
        'c': true,
        'd': 3.14,
      });
    });

    test('extracts two calls from one buffer (first only is dispatched upstream)', () {
      final calls = ToolCallParser.parse(
        'pre <|tool_call>call:a{x:1}<tool_call|> mid '
        '<|tool_call>call:b{y:<|"|>z<|"|>}<tool_call|> post',
      );
      expect(calls, hasLength(2));
      expect(calls[0].name, 'a');
      expect(calls[0].args, {'x': 1});
      expect(calls[1].name, 'b');
      expect(calls[1].args, {'y': 'z'});
    });

    test('returns empty on malformed (unclosed) call', () {
      final calls = ToolCallParser.parse(
        '<|tool_call>call:get_biometric{metric:<|"|>heart_rate<|"|>',
      );
      expect(calls, isEmpty);
    });

    test('returns empty when no marker present', () {
      expect(ToolCallParser.parse('just prose, no markup'), isEmpty);
    });

    test('records start/end offsets that bracket the full marker', () {
      const text =
          'pre <|tool_call>call:a{x:1}<tool_call|> post';
      final call = ToolCallParser.parse(text).first;
      expect(
        text.substring(call.startOffset, call.endOffset),
        '<|tool_call>call:a{x:1}<tool_call|>',
      );
    });
  });

  group('ToolCallParser.renderResponse', () {
    test('renders strings wrapped, numbers/bools bare', () {
      final out = ToolCallParser.renderResponse('get_biometric', {
        'value': 72,
        'unit': 'bpm',
        'confidence': 0.91,
        'declined': false,
      });
      expect(
        out,
        '<|tool_response>response:get_biometric'
        '{value:72,unit:<|"|>bpm<|"|>,confidence:0.91,declined:false}'
        '<tool_response|>',
      );
    });

    test('renders empty result map', () {
      expect(
        ToolCallParser.renderResponse('show_cpr_tutorial', {}),
        '<|tool_response>response:show_cpr_tutorial{}<tool_response|>',
      );
    });
  });

  group('ToolCallParser.stripMarkup', () {
    test('removes a complete tool_call', () {
      expect(
        ToolCallParser.stripMarkup(
          'before <|tool_call>call:a{x:1}<tool_call|> after',
        ),
        'before  after',
      );
    });

    test('removes a tool_response block too', () {
      expect(
        ToolCallParser.stripMarkup(
          'before <|tool_response>response:a{x:1}<tool_response|> after',
        ),
        'before  after',
      );
    });
  });

  group('ToolSchema.renderGemma4Declaration', () {
    test('golden: get_biometric with enum arg', () {
      const schema = ToolSchema(
        name: 'get_biometric',
        description: 'Get a vital',
        args: <ToolArg>[
          ToolArg(
            name: 'metric',
            type: ToolArgType.string,
            description: 'Which one',
            enumValues: <String>['heart_rate', 'spo2'],
          ),
        ],
      );
      expect(
        schema.renderGemma4Declaration(),
        '<|tool>declaration:get_biometric{'
        'description:<|"|>Get a vital<|"|>,'
        'parameters:{type:<|"|>OBJECT<|"|>,'
        'properties:{'
        'metric:{type:<|"|>STRING<|"|>,description:<|"|>Which one (one of: heart_rate|spo2)<|"|>}'
        '},'
        'required:[<|"|>metric<|"|>]'
        '}}<tool|>',
      );
    });

    test('golden: no-args tool', () {
      const schema = ToolSchema(
        name: 'show_cpr_tutorial',
        description: 'Open the CPR lesson',
        args: <ToolArg>[],
      );
      expect(
        schema.renderGemma4Declaration(),
        '<|tool>declaration:show_cpr_tutorial{'
        'description:<|"|>Open the CPR lesson<|"|>,'
        'parameters:{type:<|"|>OBJECT<|"|>}'
        '}<tool|>',
      );
    });
  });

  group('round-trip', () {
    test('parser handles output of renderResponse-shaped input loosely', () {
      // We only require that strings in <|"|>...<|"|> survive parsing.
      const text =
          '<|tool_call>call:request_help_nearby{'
          'case_summary:<|"|>chest pain<|"|>,urgency:<|"|>critical<|"|>'
          '}<tool_call|>';
      final calls = ToolCallParser.parse(text);
      expect(calls.first.args, {
        'case_summary': 'chest pain',
        'urgency': 'critical',
      });
    });
  });
}
