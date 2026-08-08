import 'package:flutter_test/flutter_test.dart';

import '../lib/core/providers/demo_state.dart';
import '../lib/features/ai_chat/tools/tool_definitions.dart';

void main() {
  test('demo mode and generated readings stay disabled', () {
    final demo = DemoState.instance;
    demo.clearReadings();

    expect(demo.isDemoMode, isFalse);
    demo.toggle();
    demo.setEnabled(true);
    demo.generateMockReadings();

    expect(demo.isDemoMode, isFalse);
    expect(demo.readings, isEmpty);
  });

  test('ordinary medical questions do not receive tool declarations', () {
    expect(shouldUseRescateTools('Normal blood pressure range?'), isFalse);
    expect(shouldUseRescateTools('What is a normal heart rate?'), isFalse);
    expect(
      shouldUseRescateTools('What should I do for a severe burn?'),
      isFalse,
    );
    expect(shouldUseRescateTools('Please measure my heart rate'), isTrue);
    expect(shouldUseRescateTools('Open the CPR tutorial'), isTrue);
  });
}
